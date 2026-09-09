# frozen_string_literal: true

require "spec_helper"

# T009/T010 [US2] — the outcome taxonomy a merchant depends on (FR-005, FR-007,
# SC-005): a returned record is a BUSINESS outcome (BML answered); a raised
# error is a TRANSPORT/VALIDATION outcome. The library never converts one into
# the other, and an AvailabilityError always names the transaction to reconcile.
RSpec.describe BMLConnect::Customers, "#charge — outcome taxonomy" do
  let(:client) { build_client }
  let(:customers) { client.customers }
  let(:charge_url) { customers_url(client, "/charge") }

  def json(body, status)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def charge!
    customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "tok_9")
  end

  it "RETURNS a record on a 200 in a success state (business outcome)" do
    stub_request(:post, charge_url).to_return(json({ id: "txn_456", state: "CONFIRMED" }, 200))
    result = charge!
    expect(result).to be_a(BMLConnect::Models::TransactionRecord)
    expect(result.state).to eq("CONFIRMED")
  end

  it "RETURNS a record on a 200 in a failed state — a decline is not raised (FR-007)" do
    stub_request(:post, charge_url).to_return(json({ id: "txn_456", state: "FAILED" }, 200))
    result = charge!
    expect(result).to be_a(BMLConnect::Models::TransactionRecord)
    expect(result.state).to eq("FAILED")
  end

  it "RAISES on a transport failure — never returns a record (FR-007)" do
    stub_request(:post, charge_url).to_timeout
    expect { charge! }.to raise_error(BMLConnect::AvailabilityError)
  end

  it "an AvailabilityError names the transaction_id so the caller can reconcile (FR-005)" do
    stub_request(:post, charge_url).to_timeout
    expect { charge! }
      .to raise_error(BMLConnect::AvailabilityError, /txn_456/)
  end

  it "the AvailabilityError message tells the caller to retrieve, not re-charge" do
    stub_request(:post, charge_url).to_timeout
    expect { charge! }
      .to raise_error(BMLConnect::AvailabilityError, /retrieve the transaction|reconcile/i)
  end
end
