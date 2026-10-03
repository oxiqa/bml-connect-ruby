# frozen_string_literal: true

require "spec_helper"

# T012 [US1] — the returned value object, in isolation.
#
# The decisive assertion here is an ABSENCE: no reader returns the raw body or a
# payload-shaped object (FR-004a, SC-008i). A `result.payload` would invite
# `result.payload[:state]` — a status read from an untrusted source — and defeat
# the entire feature. The missing accessor IS the control.
RSpec.describe BMLConnect::Models::StatusChangeResult do
  let(:record) do
    BMLConnect::Models::TransactionRecord.new(
      id: "txn_1", state: "PAID", updated: "2026-09-27T10:00:00Z"
    )
  end

  subject(:result) do
    described_class.new(
      transaction_id: "txn_1",
      transaction: record,
      claimed_status: "PENDING",
      disagreed: true,
      rechecked: true,
      advisory_http_status: 200
    )
  end

  it "exposes the identifier and the authoritative record" do
    expect(result.transaction_id).to eq("txn_1")
    expect(result.transaction).to equal(record)
  end

  it "delegates status to the authoritative record, verbatim" do
    expect(result.status).to eq("PAID")
  end

  it "reports the time of the change from the record" do
    expect(result.changed_at).to eq("2026-09-27T10:00:00Z")
  end

  it "carries the payload's claim as a diagnostic, and the disagreement flags" do
    expect(result.claimed_status).to eq("PENDING")
    expect(result).to be_disagreed
    expect(result).to be_rechecked
  end

  it "carries the advisory HTTP status" do
    expect(result.advisory_http_status).to eq(200)
  end

  it "coerces the flags to real booleans" do
    plain = described_class.new(transaction_id: "t", transaction: record)
    expect(plain.disagreed?).to be(false)
    expect(plain.rechecked?).to be(false)
  end

  describe "payload-derived data is masked (FR-011)" do
    it "scrubs a card-like claimed status" do
      leaky = described_class.new(
        transaction_id: "txn_1", transaction: record, claimed_status: "PAID #{WebhooksHelpers::PAN}"
      )
      expect(leaky.claimed_status).not_to include(WebhooksHelpers::PAN)
      expect(leaky.claimed_status).to include("[FILTERED]")
    end
  end

  describe "no route to an unmasked inbound field (SC-008i)" do
    it "exposes no payload, body, headers or raw reader" do
      forbidden = %i[payload body headers raw raw_body inbound notification]
      expect(described_class.public_instance_methods(false) & forbidden).to be_empty
    end

    it "does not respond to any of them" do
      %i[payload body headers raw].each do |reader|
        expect(result).not_to respond_to(reader), "#{reader} must not be reachable"
      end
    end

    it "keeps to_h to the whitelist, with no payload-shaped entry" do
      expect(result.to_h.keys).to eq(
        %i[transaction_id status changed_at claimed_status disagreed rechecked advisory_http_status transaction]
      )
    end

    it "keeps inspect free of anything payload-shaped" do
      expect(result.inspect).to include("txn_1")
      expect(result.inspect).not_to match(/payload|raw/i)
    end
  end

  describe "value semantics" do
    it "is equal to an identically-built result" do
      twin = described_class.new(
        transaction_id: "txn_1", transaction: record, claimed_status: "PENDING",
        disagreed: true, rechecked: true, advisory_http_status: 200
      )
      expect(result).to eq(twin)
      expect(result.hash).to eq(twin.hash)
    end

    it "differs when the authoritative status differs" do
      other_record = BMLConnect::Models::TransactionRecord.new(id: "txn_1", state: "CANCELLED")
      other = described_class.new(transaction_id: "txn_1", transaction: other_record)
      expect(result).not_to eq(other)
    end
  end
end
