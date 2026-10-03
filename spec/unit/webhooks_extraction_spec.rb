# frozen_string_literal: true

require "spec_helper"

# T011 [US1] — FR-002/002a/002b/002c: the [UNVERIFIED] candidate list, the
# caller override that outranks it, and the refusal to guess.
RSpec.describe BMLConnect::Webhooks, "identifier extraction" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }

  describe "the built-in candidate list (all [UNVERIFIED])" do
    it "documents exactly three candidates, in resolution order" do
      expect(BMLConnect::Webhooks::ID_CANDIDATES).to eq(%i[transactionId transaction_id id])
    end

    it "resolves transactionId first — the spelling BML uses everywhere it is documented" do
      stub_retrieve(client, "txn_first")
      body = json_body(transactionId: "txn_first", transaction_id: "txn_second", id: "txn_third")
      expect(webhooks.handle(body: body, headers: json_headers).transaction_id).to eq("txn_first")
    end

    it "falls through to transaction_id" do
      stub_retrieve(client, "txn_snake")
      body = json_body(transaction_id: "txn_snake", id: "txn_third")
      expect(webhooks.handle(body: body, headers: json_headers).transaction_id).to eq("txn_snake")
    end

    it "falls through to id" do
      stub_retrieve(client, "txn_bare")
      expect(webhooks.handle(body: json_body(id: "txn_bare"), headers: json_headers).transaction_id)
        .to eq("txn_bare")
    end

    it "accepts string keys as well as symbols (a form body gives strings)" do
      stub_retrieve(client, "txn_1")
      expect(webhooks.handle(body: form_body, headers: form_headers).transaction_id).to eq("txn_1")
    end
  end

  describe "a candidate that is present but not a usable identifier is skipped" do
    it "skips a nested object and uses the next candidate" do
      stub_retrieve(client, "txn_ok")
      body = JSON.generate(transactionId: { nested: "x" }, transaction_id: "txn_ok")
      expect(webhooks.handle(body: body, headers: json_headers).transaction_id).to eq("txn_ok")
    end

    it "skips an array, a number and a blank string" do
      stub_retrieve(client, "txn_ok")
      body = JSON.generate(transactionId: [1], transaction_id: "   ", id: "txn_ok")
      expect(webhooks.handle(body: body, headers: json_headers).transaction_id).to eq("txn_ok")
    end

    it "skips a numeric id rather than coercing it — a made-up id would only fail one call later" do
      body = JSON.generate(id: 12_345)
      expect { webhooks.handle(body: body, headers: json_headers) }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:transaction_id) }
      expect_no_retrieve(client, "12345")
    end
  end

  describe "no identifier at all — raise rather than guess (FR-002)" do
    it "raises ValidationError(field: :transaction_id) with ZERO remote calls" do
      body = JSON.generate(state: "PAID", localId: "SUB-1")
      expect { webhooks.handle(body: body, headers: json_headers) }
        .to raise_error(BMLConnect::ValidationError) { |e|
          expect(e.field).to eq(:transaction_id)
          expect(e.advisory_http_status).to eq(422)
        }
    end

    # localId is the MERCHANT's reference, not BML's transaction id. Retrieving
    # by it would 404 onto the permanent-advisory path — a plausible-looking
    # candidate producing a confidently wrong outcome.
    it "never treats localId as a candidate" do
      expect(BMLConnect::Webhooks::ID_CANDIDATES).not_to include(:localId)
    end
  end

  describe "a caller-supplied extractor (FR-002b/002c)" do
    it "is used, and the built-in list is NOT consulted even when transactionId is present" do
      stub_retrieve(client, "txn_from_caller")
      body = json_body(transactionId: "txn_builtin", weird: "txn_from_caller")

      result = webhooks.handle(
        body: body, headers: json_headers,
        extract_id: ->(payload, _headers) { payload[:weird] }
      )

      expect(result.transaction_id).to eq("txn_from_caller")
      expect_no_retrieve(client, "txn_builtin")
    end

    # SC-011b: headers are passed precisely so an identifier arriving outside the
    # body does not block the merchant the override exists for.
    it "receives the normalized headers, so an identifier in a header resolves" do
      stub_retrieve(client, "txn_header")

      result = webhooks.handle(
        body: JSON.generate(state: "PAID"),
        headers: { "X-BML-Transaction-Id" => "txn_header", "Content-Type" => "application/json" },
        extract_id: ->(_payload, headers) { headers["x-bml-transaction-id"] }
      )

      expect(result.transaction_id).to eq("txn_header")
    end

    it "receives a deeply symbolized payload, so dig works as documented" do
      stub_retrieve(client, "txn_nested")

      result = webhooks.handle(
        body: JSON.generate(transaction: { id: "txn_nested" }),
        headers: json_headers,
        extract_id: ->(payload, _headers) { payload.dig(:transaction, :id) }
      )

      expect(result.transaction_id).to eq("txn_nested")
    end

    # SC-011c: returning nothing is the same loud failure as an exhausted list.
    it "raises with ZERO remote calls when the extractor returns nil" do
      expect do
        webhooks.handle(body: json_body, headers: json_headers, extract_id: ->(_p, _h) { nil })
      end.to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:transaction_id) }
      expect_no_retrieve(client)
    end

    it "raises when the extractor returns something that is not a string" do
      expect do
        webhooks.handle(body: json_body, headers: json_headers, extract_id: ->(_p, _h) { { id: 1 } })
      end.to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:transaction_id) }
    end
  end

  describe "claimed status candidates (FR-010c)" do
    it "documents state then status, both [UNVERIFIED]" do
      expect(BMLConnect::Webhooks::STATUS_CANDIDATES).to eq(%i[state status])
    end

    it "reads state, then status" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      expect(webhooks.handle(body: json_body(id: "txn_1", state: "PAID"), headers: json_headers)
        .claimed_status).to eq("PAID")

      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      expect(webhooks.handle(body: json_body(id: "txn_1", status: "PAID"), headers: json_headers)
        .claimed_status).to eq("PAID")
    end

    it "leaves claimed_status nil when the payload carries no comparable status" do
      stub_retrieve(client, "txn_1")
      expect(webhooks.handle(body: json_body(id: "txn_1"), headers: json_headers).claimed_status)
        .to be_nil
    end
  end
end
