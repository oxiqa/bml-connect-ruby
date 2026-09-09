# frozen_string_literal: true

require "spec_helper"
require_relative "support"

# T013/T017/T021/T030 — end-to-end UAT verification for the v2 surface.
#
# OPT-IN and credential-gated (:integration): skips cleanly unless BML_RUN_UAT=1
# and a UAT key are present. A successful run is the evidence needed to close the
# verification table in contracts/bml-remote.md and to resolve [UNVERIFIED] #1
# (which response field carries the hosted payment URL — T021). Until a working
# key exists these skip, which is the honest state the spec preserves: the
# available UAT key is currently rejected with PP-C-004.
#
# Run: BML_RUN_UAT=1 bundle exec rspec spec/integration/transactions_v2_uat_spec.rb
RSpec.describe "Transactions v2 against UAT", :integration do
  let(:client) { UATSupport.client }

  it "creates a v2 transaction and returns an id and state (US1, SC-004)" do
    txn = client.transactions.create_v2(
      amount: 100, currency: "MVR",
      redirectUrl: "https://example.mv/return", localId: "qa-#{Time.now.to_i}"
    )
    expect(txn.id).not_to be_nil
    expect(txn.state).not_to be_nil
    expect(client.base_url).to include("uat") if client.mode == "sandbox"
  end

  it "resolves the hosted payment URL, settling [UNVERIFIED] #1 (T021)" do
    txn = client.transactions.create_v2(
      amount: 100, currency: "MVR",
      redirectUrl: "https://example.mv/return", localId: "qa-#{Time.now.to_i}"
    )
    # If this raises UnverifiedFieldError, the v2 response carries none of
    # url/redirectUrl/qr.url and the field name must be recorded in the contract.
    expect { txn.payment_url }.not_to raise_error
  end

  it "round-trips create_v2 -> retrieve (US3)" do
    created = client.transactions.create_v2(amount: 100, currency: "MVR", localId: "qa-#{Time.now.to_i}")
    fetched = client.transactions.retrieve(created.id)
    expect(fetched.id).to eq(created.id)
  end

  # SC-002 (tokenization end-to-end) cannot be closed by an unattended suite: it
  # needs a human to complete the hosted payment in a browser with a UAT test
  # card, then confirm a token via client.tokens.list(customer_id). Documented
  # here as a manual step; not asserted automatically.
end
