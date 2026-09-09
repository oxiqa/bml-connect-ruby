# frozen_string_literal: true

require "spec_helper"

# T004 [US1] — local validation, the three-key body, response mapping, and
# state passthrough for Customers#charge (FR-002, FR-006, FR-008, SC-001).
RSpec.describe BMLConnect::Customers, "#charge" do
  let(:client) { build_client }
  let(:customers) { client.customers }
  let(:charge_url) { customers_url(client, "/charge") }

  def txn_body(state: "CONFIRMED")
    { id: "txn_456", amount: 10_000, currency: "MVR", state: state }
  end

  def stub_charge(status: 200, body: txn_body)
    stub_request(:post, charge_url)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "local validation (no remote call)" do
    it "rejects a blank customer_id, naming the field" do
      expect { customers.charge(customer_id: "  ", transaction_id: "txn_456", token_id: "tok_9") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
      expect(a_request(:post, charge_url)).not_to have_been_made
    end

    it "rejects a nil transaction_id, naming the field" do
      expect { customers.charge(customer_id: "cus_1", transaction_id: nil, token_id: "tok_9") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:transaction_id) }
      expect(a_request(:post, charge_url)).not_to have_been_made
    end

    it "rejects a missing token_id, naming the field" do
      expect { customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:token_id) }
      expect(a_request(:post, charge_url)).not_to have_been_made
    end
  end

  describe "PAN screening before any remote call (FR-008)" do
    it "rejects a card number pasted into any id field, naming it" do
      expect { customers.charge(customer_id: "4111 1111 1111 1111", transaction_id: "txn_456", token_id: "tok_9") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
      expect(a_request(:post, charge_url)).not_to have_been_made
    end

    it "rejects an actor reference that looks like a PAN" do
      expect do
        customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "tok_9",
                         actor: "4111111111111111")
      end.to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:actor) }
      expect(a_request(:post, charge_url)).not_to have_been_made
    end
  end

  describe "request body (FR-002, FR-003)" do
    it "sends exactly customerId, transactionId, tokenId — no amount, no extras" do
      stub_charge
      customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "tok_9")

      expect(
        a_request(:post, charge_url).with do |req|
          body = JSON.parse(req.body)
          body == { "customerId" => "cus_1", "transactionId" => "txn_456", "tokenId" => "tok_9" }
        end
      ).to have_been_made
    end
  end

  describe "success path (FR-006)" do
    it "returns a whitelisted TransactionRecord carrying the transaction id" do
      stub_charge
      result = customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "tok_9")

      expect(result).to be_a(BMLConnect::Models::TransactionRecord)
      expect(result.id).to eq("txn_456")
    end

    it "passes state through verbatim, whatever the string" do
      stub_charge(body: txn_body(state: "AN_UNVERIFIED_STATE"))
      result = customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "tok_9")

      expect(result.state).to eq("AN_UNVERIFIED_STATE")
    end
  end
end
