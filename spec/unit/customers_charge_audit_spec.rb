# frozen_string_literal: true

require "spec_helper"

# T011 [US2] — every charge emits an audit record, FAILURES INCLUDED (FR-010,
# FR-011, SC-002, SC-006). The record names the transaction and token, carries
# no card data, and for a failure is written BEFORE the error is re-raised so a
# raise never loses the trail.
RSpec.describe BMLConnect::Customers, "#charge — auditing" do
  let(:client) { build_client }
  let(:customers) { client.customers }
  let(:charge_url) { customers_url(client, "/charge") }

  def json(body, status)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def charge!(actor: nil)
    customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "tok_9", actor: actor)
  end

  it "audits a SUCCESS, naming the transaction and token" do
    stub_request(:post, charge_url).to_return(json({ id: "txn_456", state: "CONFIRMED" }, 200))
    charge!(actor: "billing:cron")

    expect(log_output).to include("charge")
    expect(log_output).to include("success")
    expect(log_output).to include("txn_456")
    expect(log_output).to include("tok_9")
    expect(log_output).to include("billing:cron")
  end

  it "audits a DECLINE (non-2xx business rejection) before re-raising" do
    stub_request(:post, charge_url).to_return(json({ message: "declined" }, 400))
    expect { charge! }.to raise_error(BMLConnect::ValidationError)

    expect(log_output).to include("charge")
    expect(log_output).to include("declined")
  end

  it "audits a local VALIDATION FAILURE (no remote call) before re-raising" do
    expect { customers.charge(customer_id: "", transaction_id: "txn_456", token_id: "tok_9") }
      .to raise_error(BMLConnect::ValidationError)

    expect(log_output).to include("charge")
    expect(log_output).to include("validation_error")
    expect(a_request(:post, charge_url)).not_to have_been_made
  end

  it "audits an AVAILABILITY FAILURE before re-raising" do
    stub_request(:post, charge_url).to_timeout
    expect { charge! }.to raise_error(BMLConnect::AvailabilityError)

    expect(log_output).to include("charge")
    expect(log_output).to match(/"outcome":"error"/)
  end

  it "never lets a card number reach the audit line" do
    expect do
      customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "4111 1111 1111 1111")
    end.to raise_error(BMLConnect::ValidationError)

    expect(log_output).to include("charge")
    expect(log_output).not_to include("4111")
    expect(log_output).to include("[FILTERED]")
  end
end
