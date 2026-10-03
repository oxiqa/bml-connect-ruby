# frozen_string_literal: true

require "spec_helper"

# T023 [US2] — the defining threat. A merchant's notification URL is, by
# necessity, publicly reachable; anyone who finds it can post to it.
RSpec.describe BMLConnect::Webhooks, "refusing to act on a forgery" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }

  # SC-002: the single most important test in the feature.
  it "reports UNPAID when a forgery claims paid and BML says otherwise" do
    stub_retrieve(client, "txn_1", transaction_body(state: "CANCELLED"))

    result = webhooks.handle(body: json_body(transactionId: "txn_1", state: "PAID"),
                             headers: json_headers)

    expect(result.status).to eq("CANCELLED")
    expect(result.claimed_status).to eq("PAID")
    expect(result).to be_disagreed
  end

  # SC-003: no result is ever produced without a retrieve.
  it "never produces a result without having retrieved" do
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
    webhooks.handle(body: json_body, headers: json_headers)
    expect(retrieve_count(client)).to be >= 1
  end

  # FR-008: no degradation to the payload's claims, ever.
  describe "when the retrieve fails, it raises rather than falling back" do
    it "raises AvailabilityError instead of reporting the payload's claim" do
      stub_retrieve_timeout(client)

      expect { webhooks.handle(body: json_body(transactionId: "txn_1", state: "PAID"), headers: json_headers) }
        .to raise_error(BMLConnect::AvailabilityError)
    end

    it "raises NotFoundError for a forged identifier, distinguishable from a transport failure" do
      stub_retrieve_failure(client, "txn_forged", status: 404)

      expect { webhooks.handle(body: json_body(transactionId: "txn_forged", state: "PAID"), headers: json_headers) }
        .to raise_error(BMLConnect::NotFoundError)
    end
  end

  # A replay returns CURRENT truth rather than stale truth, which substantially
  # defuses it — the library still cannot deduplicate on the caller's behalf.
  it "answers a replayed old notification with the current authoritative status" do
    stub_retrieve(client, "txn_1", transaction_body(state: "CONFIRMED"))

    replay = json_body(transactionId: "txn_1", state: "INITIATED")
    expect(webhooks.handle(body: replay, headers: json_headers).status).to eq("CONFIRMED")
  end
end
