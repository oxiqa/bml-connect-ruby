# frozen_string_literal: true

require "spec_helper"

# T006 [US1] — the charge is NEVER auto-retried (FR-004, SC-004). No idempotency
# key is documented, so a retry could take payment twice. Every failure mode
# makes EXACTLY ONE HTTP attempt. build_client wires retry_backoff: 0.
RSpec.describe BMLConnect::Customers, "#charge — no retry" do
  let(:client) { build_client }
  let(:customers) { client.customers }
  let(:charge_url) { customers_url(client, "/charge") }

  def charge!
    customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "tok_9")
  end

  it "makes exactly one attempt on a connection timeout, then raises" do
    stub = stub_request(:post, charge_url).to_timeout
    expect { charge! }.to raise_error(BMLConnect::AvailabilityError)
    expect(stub).to have_been_requested.once
  end

  it "makes exactly one attempt on a 500, then raises (no retry despite a transient status)" do
    stub = stub_request(:post, charge_url)
           .to_return(status: 500, body: { message: "down" }.to_json,
                      headers: { "Content-Type" => "application/json" })
    expect { charge! }.to raise_error(BMLConnect::AvailabilityError)
    expect(stub).to have_been_requested.once
  end

  it "makes exactly one attempt on a connection reset, then raises" do
    stub = stub_request(:post, charge_url).to_raise(Faraday::ConnectionFailed.new("reset"))
    expect { charge! }.to raise_error(BMLConnect::AvailabilityError)
    expect(stub).to have_been_requested.once
  end

  it "makes exactly one attempt on a 429, then raises (no retry despite a transient status)" do
    stub = stub_request(:post, charge_url)
           .to_return(status: 429, body: { message: "slow down" }.to_json,
                      headers: { "Content-Type" => "application/json" })
    expect { charge! }.to raise_error(BMLConnect::RateLimitError)
    expect(stub).to have_been_requested.once
  end
end
