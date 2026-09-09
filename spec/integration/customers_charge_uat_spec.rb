# frozen_string_literal: true

require "spec_helper"
require_relative "support"

# T008 [US1] — end-to-end UAT verification for a stored-card charge.
#
# OPT-IN and credential-gated: every example is tagged :integration and skips
# unless a UAT key is present AND BML_RUN_UAT=1 (see integration/support). It
# also needs a customer with a GENUINELY stored card — which requires a human to
# complete a hosted payment in a browser first; no suite can create one.
#
# A successful run is the evidence needed to resolve the money-movement
# [UNVERIFIED] markers and close the verification table in
# contracts/bml-remote.md:
#   - T001  which identifier `tokenId` expects (Token#id vs Token#token) ⛔ RELEASE GATE
#   - T013  whether a decline is 200-with-failed-state or a non-2xx status
#   - T014  whether charging the same transaction twice is rejected or double-charges
#   - T015  whether a deleted token is rejected with a distinguishable error
#   - T016  whether a token/customer mismatch is rejected
#
# Run: BML_RUN_UAT=1 bundle exec rspec spec/integration/customers_charge_uat_spec.rb
RSpec.describe "Stored-card charge against UAT", :integration do
  let(:client) { UATSupport.client }
  let(:customer_id) { ENV["BML_CUSTOMER_ID"] }
  let(:token_id) { ENV["BML_TOKEN_ID"] }

  before do
    skip "set BML_CUSTOMER_ID to a customer with a stored card" if customer_id.to_s.strip.empty?
    skip "set BML_TOKEN_ID to that customer's stored token id" if token_id.to_s.strip.empty?
  end

  # Create a fresh, small transaction to charge. A new transaction per example
  # keeps the [UNVERIFIED] cases from confounding each other (research R5).
  def fresh_transaction(amount: 100, local_id: "UAT-CHARGE")
    client.transactions.create_v2(
      amount: amount, currency: "MVR", customerId: customer_id, localId: local_id
    )
  end

  it "charges a stored card and returns a transaction with a resolved state (US1, SC-001/SC-003)" do
    txn = fresh_transaction
    charged = client.customers.charge(customer_id: customer_id, transaction_id: txn.id, token_id: token_id,
                                      actor: "uat-suite")

    expect(charged).to be_a(BMLConnect::Models::TransactionRecord)
    expect(charged.state).not_to be_nil
    expect(client.base_url).to include("uat") if client.mode == "sandbox" # environment isolation (FR-012)
    # T001: confirm here that BML_TOKEN_ID was Token#id; if this errors with a
    # not-found/invalid-token, retry with Token#token on a BRAND-NEW transaction
    # and record which identifier BML accepted, in contracts/bml-remote.md.
    # T013: record whether a decline arrives as 200-with-failed-state or non-2xx.
  end

  # T014 — money-movement safety. Charge the SAME transaction twice. Record
  # whether BML rejects the second attempt or double-charges. If it double-
  # charges, add a prominent warning to contracts/library-api.md and the README.
  it "records whether charging the same transaction twice is rejected (T014)" do
    skip "destructive: set BML_RUN_UAT_DESTRUCTIVE=1 to exercise a double charge" \
      unless %w[1 true yes].include?(ENV.fetch("BML_RUN_UAT_DESTRUCTIVE", "").strip.downcase)

    txn = fresh_transaction(local_id: "UAT-DOUBLE")
    client.customers.charge(customer_id: customer_id, transaction_id: txn.id, token_id: token_id)

    # The second attempt is the observation. Do NOT assume a rejection.
    begin
      second = client.customers.charge(customer_id: customer_id, transaction_id: txn.id, token_id: token_id)
      warn "[T014] second charge SUCCEEDED — investigate double-charge risk: state=#{second.state}"
    rescue BMLConnect::Error => e
      warn "[T014] second charge rejected with #{e.class}: #{e.message}"
    end
  end

  # T015 — a deleted token must be rejected with a distinguishable error.
  it "rejects a charge against a deleted token (T015)" do
    deletable = ENV["BML_DELETABLE_TOKEN_ID"]
    skip "set BML_DELETABLE_TOKEN_ID (will be deleted) to run the deleted-token check" if deletable.to_s.strip.empty?

    client.tokens.delete(customer_id, deletable, actor: "uat-suite")
    txn = fresh_transaction(local_id: "UAT-DELETED-TOKEN")

    expect do
      client.customers.charge(customer_id: customer_id, transaction_id: txn.id, token_id: deletable)
    end.to raise_error(BMLConnect::Error)
  end

  # T016 — SECURITY. A token paired with the WRONG customer id must be rejected.
  # If the charge succeeds, stop and report to BML: tokens would be chargeable
  # across customers.
  it "rejects a charge pairing a token with a mismatched customer id (T016, SECURITY)" do
    other = ENV["BML_OTHER_CUSTOMER_ID"]
    skip "set BML_OTHER_CUSTOMER_ID to a second customer to run the mismatch check" if other.to_s.strip.empty?

    txn = client.transactions.create_v2(amount: 100, currency: "MVR", customerId: other, localId: "UAT-MISMATCH")
    expect do
      client.customers.charge(customer_id: other, transaction_id: txn.id, token_id: token_id)
    end.to raise_error(BMLConnect::Error)
  end
end
