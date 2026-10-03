# frozen_string_literal: true

require "spec_helper"

# T026 [US2] — FR-011/011a, SC-005/SC-005a.
#
# Two halves, and BOTH matter. Card-like data must never reach a log, an audit
# record, an error message, or a result — and the delivery must still be HANDLED
# rather than rejected. The PAN screen matches any Luhn-valid 13-19 digit run, so
# rejecting would let a coincidental merchant reference permanently discard a
# genuine payment confirmation (FR-011a).
RSpec.describe BMLConnect::Webhooks, "inbound card-data screening" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }
  let(:pan) { WebhooksHelpers::PAN }

  describe "the delivery is still handled (FR-011a, SC-005a)" do
    it "handles a payload carrying a Luhn-valid card number normally" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

      result = webhooks.handle(
        body: json_body(transactionId: "txn_1", state: "PAID", cardNumber: pan),
        headers: json_headers
      )

      expect(result.status).to eq("PAID")
      expect(retrieve_count(client)).to eq(1)
    end

    it "does not reject a card-like value sitting in the claimed status" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

      result = webhooks.handle(
        body: json_body(transactionId: "txn_1", state: "PAID #{pan}"),
        headers: json_headers
      )

      expect(result.status).to eq("PAID")
    end
  end

  describe "and the number reaches no output (FR-011, SC-005)" do
    it "keeps it out of the audit record on an accepted delivery" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      webhooks.handle(body: json_body(transactionId: "txn_1", state: "PAID", cardNumber: pan),
                      headers: json_headers)

      expect(webhook_log).not_to include(pan)
      expect(webhook_log).to include("[FILTERED]")
    end

    it "keeps it off the result" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      result = webhooks.handle(body: json_body(transactionId: "txn_1", state: "PAID #{pan}"),
                               headers: json_headers)

      expect(result.to_h.to_s).not_to include(pan)
      expect(result.inspect).not_to include(pan)
    end

    it "keeps it out of the audit record on a malformed delivery" do
      expect { webhooks.handle(body: "garbage #{pan}", headers: json_headers) }
        .to raise_error(BMLConnect::ValidationError)

      expect(webhook_log).not_to include(pan)
    end

    it "keeps it out of the audit record on a rejected delivery" do
      secured = build_webhook_client(secret: "right")
      begin
        secured.webhooks.handle(body: json_body(transactionId: "txn_1", state: "PAID", cardNumber: pan),
                                headers: json_headers, presented_secret: "wrong")
      rescue BMLConnect::WebhookRejectedError # rubocop:disable Lint/SuppressedException
      end

      expect(webhook_log).not_to include(pan)
    end

    it "keeps it out of an error message when a retrieve fails" do
      stub_retrieve_failure(client, "txn_1", status: 500, body: { message: "failure near #{pan}" })

      expect { webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::Error) { |e| expect(e.message).not_to include(pan) }
    end
  end

  # An `actor` is caller-supplied, not BML-supplied, so it follows the library's
  # existing outbound rule: a PAN there is the caller's mistake and raises.
  describe "a card-like actor is still rejected" do
    it "raises before any remote call" do
      expect { webhooks.handle(body: json_body, headers: json_headers, actor: pan) }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:actor) }
      expect_no_retrieve(client)
    end
  end
end
