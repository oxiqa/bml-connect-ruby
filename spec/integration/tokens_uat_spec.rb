# frozen_string_literal: true

require "spec_helper"
require_relative "support"

# T012/T017/T022 — end-to-end UAT verification for stored-card tokens.
#
# OPT-IN and credential-gated: every example is tagged :integration and skips
# cleanly unless a UAT key is present AND BML_RUN_UAT=1 (see integration/support).
# A successful run is the evidence needed to resolve the [UNVERIFIED] markers and
# close the verification table in contracts/bml-remote.md (tasks T013/T018/T023/
# T026). Until a working key replaces the PP-C-004-rejected one these skip —
# the honest state the spec deliberately preserves.
#
# BML_CUSTOMER_ID must reference a customer who has completed a tokenizing
# transaction (feature 003); there is no way to create a token from the suite.
#
# Run: BML_RUN_UAT=1 bundle exec rspec spec/integration/tokens_uat_spec.rb
RSpec.describe "Stored card tokens against UAT", :integration do
  let(:client) { UATSupport.client }
  let(:customer_id) { ENV["BML_CUSTOMER_ID"] }

  before do
    skip "set BML_CUSTOMER_ID to a customer with a stored card" if customer_id.to_s.strip.empty?
  end

  it "lists a customer's tokens with a masked summary and no full PAN (US1, SC-002)" do
    list = client.tokens.list(customer_id)
    expect(list).to respond_to(:count)
    expect(list.items).to be_a(Array)

    serialized = list.map(&:to_h).to_json
    expect(BMLConnect::Masking.scrub(serialized)).to eq(serialized) # nothing PAN-like survives
    expect(client.base_url).to include("uat") if client.mode == "sandbox" # SC-004
  end

  it "round-trips list -> retrieve for the first token (US2)" do
    first = client.tokens.list(customer_id).first
    skip "customer has no stored cards" if first.nil?

    fetched = client.tokens.retrieve(customer_id, first.id)
    expect(fetched.id).to eq(first.id)
    # T013: record here which identifier tokenId refers to (Token#id vs Token#token).
  end

  # T017 [US2] SECURITY — mandatory. A valid tokenId retrieved under a DIFFERENT
  # customer id must NOT return the token. If it does, stop, do not ship, and
  # report to BML: that is a cardholder-data exposure (research R5).
  it "does not return a token when retrieved under the wrong customer id (SECURITY)" do
    other = ENV["BML_OTHER_CUSTOMER_ID"]
    skip "set BML_OTHER_CUSTOMER_ID to a second customer to run the cross-customer check" if other.to_s.strip.empty?
    first = client.tokens.list(customer_id).first
    skip "customer has no stored cards" if first.nil?

    expect { client.tokens.retrieve(other, first.id) }.to raise_error(BMLConnect::NotFoundError)
    # T018: record the not-found status/body and the cross-customer result.
  end

  it "deletes a token, then records whether it disappears or shows deleted: true (US3)" do
    skip "destructive: set BML_RUN_UAT_DESTRUCTIVE=1 to exercise delete" \
      unless %w[1 true yes].include?(ENV.fetch("BML_RUN_UAT_DESTRUCTIVE", "").strip.downcase)

    first = client.tokens.list(customer_id).first
    skip "customer has no stored cards" if first.nil?

    expect(client.tokens.delete(customer_id, first.id, actor: "uat-suite")).to be(true)
    # T022/T023: after deletion, list again and record whether the token still
    # appears with deleted: true or disappears, plus any effect on tokenAgreementId.
    client.tokens.list(customer_id)
  end
end
