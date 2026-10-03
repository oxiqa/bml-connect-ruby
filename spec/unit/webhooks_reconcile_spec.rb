# frozen_string_literal: true

require "spec_helper"

# T031 [US3] — US3-4: the fallback when a notification never arrives at all.
#
# The whole point of the trust model is that the retrieve is authoritative, so a
# lost delivery costs nothing but latency: the operator asks BML directly, with
# this feature entirely uninvolved.
RSpec.describe "reconciling a notification that never arrived" do
  let(:client) { build_webhook_client }

  it "yields the authoritative status straight from the transactions resource" do
    stub_retrieve(client, "txn_never_notified", transaction_body(id: "txn_never_notified", state: "CONFIRMED"))

    record = client.transactions.retrieve("txn_never_notified")

    expect(record.state).to eq("CONFIRMED")
    expect(retrieve_count(client, "txn_never_notified")).to eq(1)
  end

  it "needs no webhook handling to do it" do
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

    expect(client.transactions.retrieve("txn_1").state).to eq("PAID")
    expect(audit_records).to be_empty
  end
end
