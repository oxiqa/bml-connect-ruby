# frozen_string_literal: true

require "spec_helper"

# T021 [US3] — list envelope handling, count coercion, empty result.
RSpec.describe BMLConnect::Customers, "#list" do
  let(:client) { build_client }
  let(:customers) { client.customers }

  def stub_list(body)
    stub_request(:get, customers_url(client))
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "coerces a string count to an Integer" do
    stub_list(count: "2", items: [{ id: "a" }, { id: "b" }])
    list = customers.list
    expect(list.count).to eq(2)
    expect(list.count).to be_a(Integer)
  end

  it "falls back to items.size on a non-numeric count" do
    stub_list(count: "not-a-number", items: [{ id: "a" }])
    expect(customers.list.count).to eq(1)
  end

  it "returns an empty list (not an error) for a company with no customers" do
    stub_list(count: "0", items: [])
    list = customers.list
    expect(list).to be_empty
    expect(list.count).to eq(0)
  end

  it "is Enumerable over Customer value objects" do
    stub_list(count: "2", items: [{ id: "a", email: "a@example.mv" }, { id: "b", email: "b@example.mv" }])
    emails = customers.list.map(&:email)
    expect(emails).to eq(["a@example.mv", "b@example.mv"])
  end

  it "sends no query parameters (contract documents none)" do
    stub = stub_list(count: "0", items: [])
    customers.list
    expect(stub).to have_been_requested
    expect(a_request(:get, /public-customers\?/)).not_to have_been_made
  end
end
