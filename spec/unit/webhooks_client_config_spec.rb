# frozen_string_literal: true

require "spec_helper"

# T006 — the resource accessor and the two configuration knobs.
RSpec.describe BMLConnect::Client, "webhook configuration" do
  it "exposes a memoized webhooks resource" do
    client = build_webhook_client
    expect(client.webhooks).to be_a(BMLConnect::Webhooks)
    expect(client.webhooks).to equal(client.webhooks)
  end

  it "defaults the secret to nil and the re-check delay to 3 seconds (FR-010b, SC-008m)" do
    client = BMLConnect::Client.new(api_key: "k", app_id: "a", mode: "sandbox")
    expect(client.webhook_secret).to be_nil
    expect(client.webhook_recheck_delay).to eq(3)
    expect(BMLConnect::Client::DEFAULT_WEBHOOK_RECHECK_DELAY).to eq(3)
  end

  it "accepts both options and keeps them away from Faraday, which rejects unknown keys" do
    client = build_webhook_client(secret: "s3cret", recheck_delay: 0)
    expect(client.webhook_secret).to eq("s3cret")
    expect(client.webhook_recheck_delay).to eq(0)
    expect(client.http_client).to be_a(Faraday::Connection)
  end

  it "allows zero to disable the re-check entirely" do
    expect(build_webhook_client(recheck_delay: 0).webhook_recheck_delay).to eq(0)
  end
end
