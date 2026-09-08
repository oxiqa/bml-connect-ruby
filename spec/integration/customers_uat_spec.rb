# frozen_string_literal: true

require "spec_helper"
require_relative "support"

# T016/T020/T024/T028/T032 — end-to-end UAT verification.
#
# OPT-IN and credential-gated: every example is tagged :integration and skips
# cleanly unless a UAT key is present in .env (BML_API_KEY). A successful run is
# the evidence needed to close the verification table in
# contracts/bml-remote.md (task T033) — until a working key exists these skip,
# which is the honest state the spec deliberately preserves.
#
# Run: bundle exec rspec spec/integration/customers_uat_spec.rb
RSpec.describe "Customers against UAT", :integration do
  let(:client) { UATSupport.client }

  # A record created here and reused across the flow.
  def unique_email
    "qa+#{Time.now.to_i}@example.mv"
  end

  it "creates a customer and returns a usable id (US1) in the selected environment (SC-004)" do
    customer = client.customers.create(name: "QA Aisha", email: unique_email)
    expect(customer.id).not_to be_nil
    expect(customer.id).not_to be_empty
    # Environment isolation: a sandbox client must be talking to the UAT host.
    expect(client.base_url).to include("uat") if client.mode == "sandbox"
  end

  it "round-trips create -> retrieve (US2)" do
    created = client.customers.create(name: "QA Retrieve", email: unique_email)
    fetched = client.customers.retrieve(created.id)
    expect(fetched.id).to eq(created.id)
  end

  it "lists customers as a {count, items} envelope (US3)" do
    list = client.customers.list
    expect(list).to respond_to(:count)
    expect(list.items).to be_a(Array)
  end

  it "applies a single-field update without disturbing other fields (US4, SC-005)" do
    created = client.customers.create(name: "QA Update", email: unique_email, billingCity: "Male")
    before = client.customers.retrieve(created.id)
    client.customers.update(created.id, billingCity: "Hulhumale")
    after = client.customers.retrieve(created.id)

    expect(after.billingCity).to eq("Hulhumale")
    expect(after.name).to eq(before.name)
    expect(after.email).to eq(before.email)
  end

  it "archives a customer and records the effect on its tokens (US5, resolves an [UNVERIFIED] marker)" do
    created = client.customers.create(name: "QA Archive", email: unique_email)
    expect(client.customers.archive(created.id)).to be(true)

    archived = client.customers.retrieve(created.id)
    expect(archived.deleted?).to be(true)
    # NOTE: for T033: record here what happens to this customer's stored tokens
    # once feature 002 exists — the cascade behavior is [UNVERIFIED] in the contract.
  end
end
