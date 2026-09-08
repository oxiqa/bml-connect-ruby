# frozen_string_literal: true

require "spec_helper"

# T017 [US2] — retrieve validation, whitelisting, archived-record handling.
RSpec.describe BMLConnect::Customers, "#retrieve" do
  let(:client) { build_client }
  let(:customers) { client.customers }

  it "rejects a blank id without a remote call" do
    expect { customers.retrieve("  ") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
    expect(a_request(:get, %r{/public-customers})).not_to have_been_made
  end

  it "rejects a nil id" do
    expect { customers.retrieve(nil) }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
  end

  it "drops unknown/sensitive keys via whitelisting" do
    body = { id: "cus_1", name: "Aisha", email: "aisha@example.mv", cardNumber: "4111111111111111" }
    stub_request(:get, customers_url(client, "/cus_1"))
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    customer = customers.retrieve("cus_1")
    expect(customer.to_h).not_to have_key(:cardNumber)
    expect(customer.name).to eq("Aisha")
  end

  it "returns an archived customer with deleted? true rather than raising" do
    body = { id: "cus_1", name: "Aisha", email: "aisha@example.mv", deleted: true }
    stub_request(:get, customers_url(client, "/cus_1"))
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

    customer = customers.retrieve("cus_1")
    expect(customer.deleted?).to be(true)
  end

  it "is not audited (read)" do
    stub_request(:get, customers_url(client, "/cus_1"))
      .to_return(status: 200, body: { id: "cus_1" }.to_json, headers: { "Content-Type" => "application/json" })
    customers.retrieve("cus_1")
    expect(log_output).not_to include("retrieve")
  end
end
