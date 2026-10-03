# frozen_string_literal: true

require "spec_helper"

# T025 [US2] — FR-009a/009b/009d/009e: the shared secret gates SPEND, not trust.
RSpec.describe BMLConnect::Webhooks, "the optional shared secret" do
  let(:client) { build_webhook_client(secret: "sup3r-s3cret") }
  let(:webhooks) { client.webhooks }

  describe "rejection costs ZERO retrieves (SC-008e)" do
    it "rejects a delivery presenting no secret value" do
      stub_retrieve(client)

      expect { webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::WebhookRejectedError)
      expect(retrieve_count(client)).to eq(0)
    end

    it "rejects a wrong presented value" do
      stub_retrieve(client)

      expect { webhooks.handle(body: json_body, headers: json_headers, presented_secret: "nope") }
        .to raise_error(BMLConnect::WebhookRejectedError)
      expect(retrieve_count(client)).to eq(0)
    end

    it "rejects a blank presented value" do
      expect { webhooks.handle(body: json_body, headers: json_headers, presented_secret: "  ") }
        .to raise_error(BMLConnect::WebhookRejectedError)
    end

    it "rejects before parsing, so an unauthenticated sender cannot even reach the parser" do
      expect { webhooks.handle(body: "total garbage", headers: json_headers) }
        .to raise_error(BMLConnect::WebhookRejectedError)
    end
  end

  describe "a matching secret changes nothing about trust (FR-009b)" do
    it "still performs the verifying retrieve" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

      result = webhooks.handle(body: json_body, headers: json_headers, presented_secret: "sup3r-s3cret")

      expect(result.status).to eq("PAID")
      expect(retrieve_count(client)).to eq(1)
    end

    # SC-008f: identical reported status with and without a secret configured.
    it "reports an identical status to the same notification handled without a secret" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      with_secret = webhooks.handle(body: json_body, headers: json_headers,
                                    presented_secret: "sup3r-s3cret")

      open_client = build_webhook_client(secret: nil)
      stub_retrieve(open_client, "txn_1", transaction_body(state: "PAID"))
      without_secret = open_client.webhooks.handle(body: json_body, headers: json_headers)

      expect(with_secret.status).to eq(without_secret.status)
      expect(with_secret.to_h).to eq(without_secret.to_h)
    end

    it "does not believe the payload's claim just because the secret matched" do
      stub_retrieve(client, "txn_1", transaction_body(state: "CANCELLED"))

      result = webhooks.handle(body: json_body(transactionId: "txn_1", state: "PAID"),
                               headers: json_headers, presented_secret: "sup3r-s3cret")

      expect(result.status).to eq("CANCELLED")
      expect(result.claimed_status).to eq("PAID")
    end
  end

  # FR-009e / SC-008j: the library reads no location of its own. BML controls the
  # callback's headers, so a merchant can realistically carry a secret only in
  # the URL it registered — and a default location would be an invention.
  describe "the library never guesses where the secret travels (FR-009e)" do
    it "rejects when the correct secret is in the headers but the caller presents nothing" do
      stub_retrieve(client)

      expect do
        webhooks.handle(
          body: json_body,
          headers: json_headers.merge("X-Webhook-Secret" => "sup3r-s3cret",
                                      "Authorization" => "sup3r-s3cret")
        )
      end.to raise_error(BMLConnect::WebhookRejectedError)
      expect(retrieve_count(client)).to eq(0)
    end

    it "never asks for the request URL" do
      expect(BMLConnect::Webhooks.instance_method(:handle).parameters.map(&:last))
        .not_to include(:url, :request_url, :query, :params)
    end
  end

  describe "with no secret configured (FR-009c)" do
    it "handles the delivery and spends a real retrieve on every inbound request" do
      open_client = build_webhook_client(secret: nil)
      stub_retrieve(open_client, "txn_1", transaction_body(state: "PAID"))

      open_client.webhooks.handle(body: json_body, headers: json_headers)
      expect(retrieve_count(open_client)).to eq(1)
    end

    it "ignores a presented value nobody asked for" do
      open_client = build_webhook_client(secret: nil)
      stub_retrieve(open_client, "txn_1", transaction_body(state: "PAID"))

      expect(open_client.webhooks.handle(body: json_body, headers: json_headers,
                                         presented_secret: "whatever").status).to eq("PAID")
    end
  end

  # FR-012: never in a log, an audit record, an error message, or on a result.
  describe "the secret never leaks (FR-012)" do
    it "keeps both values out of the rejection message" do
      expect { webhooks.handle(body: json_body, headers: json_headers, presented_secret: "nope") }
        .to raise_error(BMLConnect::WebhookRejectedError) { |e|
          expect(e.message).not_to include("sup3r-s3cret")
          expect(e.message).not_to include("nope")
        }
    end

    it "keeps both values out of the audit trail" do
      begin
        webhooks.handle(body: json_body, headers: json_headers, presented_secret: "nope")
      rescue BMLConnect::WebhookRejectedError # rubocop:disable Lint/SuppressedException
      end

      expect(webhook_log).not_to include("sup3r-s3cret")
      expect(webhook_log).not_to include("nope")
    end

    it "keeps the secret off an accepted result" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      result = webhooks.handle(body: json_body, headers: json_headers, presented_secret: "sup3r-s3cret")
      expect(result.to_h.to_s).not_to include("sup3r-s3cret")
    end
  end

  # FR-009d: resistant to timing analysis. OpenSSL.fixed_length_secure_compare is
  # unavailable on this toolchain (verified on 2.7.4), so both sides are digested
  # to a fixed 32 bytes and compared byte-by-byte (research R9).
  describe "constant-time comparison (FR-009d)" do
    it "compares digests of equal length regardless of the inputs' lengths" do
      expect(webhooks.send(:secure_equal?, "a", "a")).to be(true)
      expect(webhooks.send(:secure_equal?, "a", "a-very-much-longer-value")).to be(false)
      expect(webhooks.send(:secure_equal?, "sup3r-s3cret", "sup3r-s3cres")).to be(false)
    end

    it "does not use a plain string comparison" do
      source = File.read(File.expand_path("../../lib/bml_connect/webhooks.rb", __dir__))
      expect(source).to include("Digest::SHA256")
    end
  end
end
