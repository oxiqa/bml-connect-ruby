# frozen_string_literal: true

require "spec_helper"

# T029 [US5] — archive returns true on 204, audits, validates id.
RSpec.describe BMLConnect::Customers, "#archive" do
  let(:client) { build_client }
  let(:customers) { client.customers }

  it "returns true on a 204 with no body" do
    stub_request(:delete, customers_url(client, "/cus_1")).to_return(status: 204, body: "")
    expect(customers.archive("cus_1")).to be(true)
  end

  it "rejects a blank id without a remote call" do
    expect { customers.archive("  ") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
    expect(a_request(:delete, %r{/public-customers})).not_to have_been_made
  end

  it "emits a masked audit log line for the archive" do
    stub_request(:delete, customers_url(client, "/cus_1")).to_return(status: 204, body: "")
    customers.archive("cus_1")
    expect(log_output).to include("archive")
    expect(log_output).to include("cus_1")
  end
end
