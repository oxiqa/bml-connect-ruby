# frozen_string_literal: true

require "spec_helper"

# T025 [US4] — partial-update semantics, email shape, PAN screening, auditing.
RSpec.describe BMLConnect::Customers, "#update" do
  let(:client) { build_client }
  let(:customers) { client.customers }

  def stub_update(body: { id: "cus_1", name: "Aisha", email: "aisha@example.mv" })
    stub_request(:patch, customers_url(client, "/cus_1"))
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "sends only the supplied keys and no nulls" do
    stub = stub_request(:patch, customers_url(client, "/cus_1"))
           .with do |req|
             body = JSON.parse(req.body)
             body.keys == ["billingCity"] && body["billingCity"] == "Hulhumale"
           end
           .to_return(status: 200, body: { id: "cus_1" }.to_json, headers: { "Content-Type" => "application/json" })

    customers.update("cus_1", billingCity: "Hulhumale")
    expect(stub).to have_been_requested
  end

  it "rejects an empty change set locally with no remote call" do
    expect { customers.update("cus_1", {}) }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:changes) }
    expect(a_request(:patch, %r{/public-customers})).not_to have_been_made
  end

  it "rejects a blank id" do
    expect { customers.update("  ", billingCity: "X") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
  end

  it "applies the email shape check when email is among the changes" do
    expect { customers.update("cus_1", email: "nope") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:email) }
    expect(a_request(:patch, %r{/public-customers})).not_to have_been_made
  end

  it "screens supplied string values for card data" do
    expect { customers.update("cus_1", taxId: "4111111111111111") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:taxId) }
  end

  it "accepts update-only fields such as currency and paymentDue" do
    stub = stub_request(:patch, customers_url(client, "/cus_1"))
           .with { |req| JSON.parse(req.body).keys.sort == %w[currency paymentDue] }
           .to_return(status: 200, body: { id: "cus_1" }.to_json, headers: { "Content-Type" => "application/json" })
    customers.update("cus_1", currency: "MVR", paymentDue: 100)
    expect(stub).to have_been_requested
  end

  it "emits a masked audit log line for the update" do
    stub_update
    customers.update("cus_1", billingCity: "Hulhumale")
    expect(log_output).to include("update")
    expect(log_output).to include("cus_1")
  end
end
