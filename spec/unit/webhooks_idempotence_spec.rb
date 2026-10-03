# frozen_string_literal: true

require "spec_helper"

# FR-013/FR-014/FR-014a, SC-006/SC-006a — the coverage gap /speckit-analyze found.
#
# "Equivalent results" means EQUAL GIVEN AN UNCHANGED authoritative record. The
# literal reading — always identical — is a guarantee the library cannot keep and
# must not try to: if a transaction genuinely moves from pending to paid between
# two deliveries, the second handling MUST report the new status. Manufacturing
# identical output would require a cache that FR-013 forbids.
RSpec.describe BMLConnect::Webhooks, "handling the same notification twice" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }

  describe "against an unchanged authoritative record (SC-006)" do
    before { stub_retrieve(client, "txn_1", transaction_body(state: "PAID")) }

    it "produces equal results" do
      first = webhooks.handle(body: json_body, headers: json_headers)
      second = webhooks.handle(body: json_body, headers: json_headers)

      expect(second).to eq(first)
      expect(second.to_h).to eq(first.to_h)
    end

    it "spends exactly one retrieve per handling — no caching, no sharing" do
      webhooks.handle(body: json_body, headers: json_headers)
      expect(retrieve_count(client)).to eq(1)

      webhooks.handle(body: json_body, headers: json_headers)
      expect(retrieve_count(client)).to eq(2)
    end

    it "carries no state from the first handling into the second" do
      webhooks.handle(body: json_body, headers: json_headers)
      before_vars = webhooks.instance_variables - [:@client]

      webhooks.handle(body: json_body, headers: json_headers)

      expect(webhooks.instance_variables - [:@client]).to eq(before_vars)
      expect(before_vars).to be_empty
    end

    it "performs no side effect beyond the retrieve and the audit line" do
      transactions_before = client.transactions.object_id

      webhooks.handle(body: json_body, headers: json_headers)

      expect(client.transactions.object_id).to eq(transactions_before)
      expect(audit_records.size).to eq(1)
    end
  end

  # SC-006a: reporting current truth is the feature working, not a violation.
  describe "when the authoritative record changed in between (SC-006a)" do
    it "reports the NEW status on the second handling" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"), transaction_body(state: "PAID"))

      first = webhooks.handle(body: json_body(transactionId: "txn_1"), headers: json_headers)
      second = webhooks.handle(body: json_body(transactionId: "txn_1"), headers: json_headers)

      expect(first.status).to eq("PENDING")
      expect(second.status).to eq("PAID")
    end
  end

  # FR-014a: the library deduplicates nothing, and says so rather than implying
  # otherwise. Replay and ordering protection stay the caller's job; the
  # identifier is surfaced so they can do it.
  describe "no deduplication (FR-014a)" do
    it "handles a duplicate delivery again rather than short-circuiting it" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

      3.times { webhooks.handle(body: json_body, headers: json_headers) }

      expect(retrieve_count(client)).to eq(3)
    end

    it "offers no deduplication surface for a caller to mistake for one" do
      forbidden = %i[seen? deduplicate delivered? mark_delivered cache]
      expect(BMLConnect::Webhooks.public_instance_methods(false) & forbidden).to be_empty
    end

    it "surfaces the identifier the caller needs to deduplicate themselves" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      expect(webhooks.handle(body: json_body, headers: json_headers).transaction_id).to eq("txn_1")
    end
  end
end
