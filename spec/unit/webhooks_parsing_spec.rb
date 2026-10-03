# frozen_string_literal: true

require "spec_helper"

# T010 [US1] — FR-003/003a/003b: the two accepted body formats, the documented
# fallback order, and the rejections that cost no remote call.
#
# The published contract documents the callback's Content-Type nowhere, so both
# formats stay [UNVERIFIED] until a real delivery is observed.
RSpec.describe BMLConnect::Webhooks, "body parsing" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }

  before { stub_retrieve(client, "txn_1", transaction_body(state: "PAID")) }

  describe "selection by declared Content-Type" do
    it "parses JSON declared as application/json" do
      result = webhooks.handle(body: json_body, headers: json_headers)
      expect(result.transaction_id).to eq("txn_1")
    end

    it "parses a vendor +json suffix" do
      result = webhooks.handle(body: json_body, headers: { "Content-Type" => "application/vnd.bml+json" })
      expect(result.transaction_id).to eq("txn_1")
    end

    it "ignores Content-Type parameters such as charset" do
      result = webhooks.handle(body: json_body, headers: { "Content-Type" => "application/json; charset=utf-8" })
      expect(result.transaction_id).to eq("txn_1")
    end

    it "parses a form-encoded body declared as x-www-form-urlencoded" do
      result = webhooks.handle(body: form_body, headers: form_headers)
      expect(result.transaction_id).to eq("txn_1")
    end

    # SC-008k: the same delivery in either format must behave identically.
    it "handles a form-encoded delivery identically to its JSON equivalent" do
      json = webhooks.handle(body: json_body, headers: json_headers)
      form = webhooks.handle(body: form_body, headers: form_headers)

      expect(form.status).to eq(json.status)
      expect(form.transaction_id).to eq(json.transaction_id)
      expect(form.claimed_status).to eq(json.claimed_status)
    end
  end

  describe "fallback when the type is absent or unrecognized (research R4)" do
    # URI.decode_www_form does NOT raise on a JSON body — it returns one garbage
    # key holding the whole string (verified). Trying form first would therefore
    # mask every JSON payload instead of failing, so JSON must go first.
    it "parses a JSON body with no Content-Type at all, unmangled" do
      result = webhooks.handle(body: json_body, headers: {})
      expect(result.transaction_id).to eq("txn_1")
      expect(result.claimed_status).to eq("PAID")
    end

    it "parses a form body with no Content-Type" do
      expect(webhooks.handle(body: form_body, headers: {}).transaction_id).to eq("txn_1")
    end

    it "parses a JSON body whose declared type is unrecognized" do
      result = webhooks.handle(body: json_body, headers: { "Content-Type" => "text/plain" })
      expect(result.transaction_id).to eq("txn_1")
    end
  end

  describe "rejections — ValidationError(field: :body) with ZERO remote calls" do
    def expect_malformed(body:, headers: {})
      expect { webhooks.handle(body: body, headers: headers) }
        .to raise_error(BMLConnect::ValidationError) { |e|
          expect(e.field).to eq(:body)
          expect(e.advisory_http_status).to eq(400)
        }
      expect_no_retrieve(client)
    end

    it "rejects an empty body" do
      expect_malformed(body: "")
    end

    it "rejects a whitespace-only body" do
      expect_malformed(body: "   \n ")
    end

    it "rejects a nil body" do
      expect_malformed(body: nil)
    end

    it "rejects invalid UTF-8 bytes rather than silently scrubbing them" do
      expect_malformed(body: "{\"id\":\"\xC3\x28\"}", headers: json_headers)
    end

    it "rejects a body neither parser accepts" do
      expect_malformed(body: "not json and not a form", headers: json_headers)
    end

    # A bare JSON array or scalar parses, but there is nothing to look a field up
    # in, so it is malformed rather than unextractable.
    it "rejects a bare JSON array" do
      expect_malformed(body: "[1,2,3]", headers: json_headers)
    end

    it "rejects a bare JSON scalar" do
      expect_malformed(body: '"just a string"', headers: json_headers)
    end

    it "rejects a form-declared body carrying no field at all" do
      expect_malformed(body: "no-equals-sign-here", headers: form_headers)
    end
  end

  # Research R5: integrators pass request.headers (Rails), request.env (Rack), or
  # a plain hash. Without normalization the Content-Type selection silently
  # misses on a Rack env and every delivery lands in the fallback path — working,
  # but by accident.
  describe "header-name normalization" do
    it "resolves Content-Type, content_type, CONTENT_TYPE and Rack's HTTP_CONTENT_TYPE" do
      [
        { "Content-Type" => "application/x-www-form-urlencoded" },
        { "content_type" => "application/x-www-form-urlencoded" },
        { "CONTENT_TYPE" => "application/x-www-form-urlencoded" },
        { "HTTP_CONTENT_TYPE" => "application/x-www-form-urlencoded" }
      ].each do |headers|
        expect(webhooks.handle(body: form_body, headers: headers).transaction_id)
          .to eq("txn_1"), "failed for #{headers.keys.first}"
      end
    end

    it "accepts a whole Rack env, unrelated keys and all" do
      result = webhooks.handle(body: json_body, headers: rack_env)
      expect(result.transaction_id).to eq("txn_1")
    end

    it "tolerates a nil header hash" do
      expect(webhooks.handle(body: json_body, headers: nil).transaction_id).to eq("txn_1")
    end
  end
end
