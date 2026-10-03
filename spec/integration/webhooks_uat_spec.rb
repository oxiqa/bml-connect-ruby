# frozen_string_literal: true

require_relative "support"
require "json"

# T033 — opt-in UAT verification. Needs something no earlier feature here did:
# INBOUND network reachability from BML UAT, not only outbound calls.
#
# Two examples, both gated:
#
#   1. Replay a recorded delivery (the T001 observation) through the handler
#      against a real UAT transaction. Skips until the fixture exists.
#   2. Confirm the reconciliation fallback works live — the thing a merchant does
#      when a notification never arrives.
#
# The recording procedure is in specs/005-webhook-handler/contracts/bml-remote.md.
RSpec.describe "webhook handling against UAT", :integration do
  let(:client) { UATSupport.client }
  let(:fixture_path) { File.expand_path("../support/fixtures/webhook_delivery.txt", __dir__) }

  it "replays the recorded UAT delivery and returns an authoritative status (SC-011)" do
    unless File.exist?(fixture_path)
      skip "no observed delivery recorded yet — see contracts/bml-remote.md " \
           "'Observation procedure' (release gate T001)"
    end

    raw = File.read(fixture_path)
    body = raw.split(/\r?\n\r?\n/, 2).last.to_s
    content_type = raw[/^content-type:\s*(.+)$/i, 1].to_s.strip

    result = client.webhooks.handle(
      body: body,
      headers: content_type.empty? ? {} : { "Content-Type" => content_type }
    )

    expect(result.transaction_id).not_to be_nil
    expect(result.status).to be_a(String)
    expect(result.advisory_http_status).to eq(200)
  end

  it "reconciles a transaction directly, which is the fallback when no delivery arrives" do
    transaction_id = ENV["BML_TRANSACTION_ID"]
    skip "set BML_TRANSACTION_ID to a real UAT transaction to run this" if transaction_id.to_s.strip.empty?

    record = client.transactions.retrieve(transaction_id)
    expect(record.id).to eq(transaction_id)
    expect(record.state).to be_a(String)
  end
end
