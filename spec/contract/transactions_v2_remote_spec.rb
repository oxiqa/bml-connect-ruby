# frozen_string_literal: true

require "spec_helper"

# T009/T010/T015/T019/T023/T025/T026 — the remote HTTP contract for the v2
# surface. Every stub URL is derived from client.base_url (research R10). Auth is
# the raw Authorization header, no Bearer, no X-App-Id, and NO signature on v2
# (FR-012/FR-013). Create and capture make exactly one attempt (FR-016/SC-007).
RSpec.describe BMLConnect::Transactions, "v2 remote contract" do
  let(:client) { build_client }
  let(:transactions) { client.transactions }

  describe "create_v2 request shape (FR-001/012/013)" do
    it "POSTs to /public/v2/transactions with the raw Authorization header, no Bearer, no X-App-Id, no signature" do
      stub = stub_request(:post, v2_create_url(client))
             .with(headers: { "Authorization" => "test-key" }) do |req|
               expect(req.headers).not_to have_key("X-App-Id")
               expect(req.headers["Authorization"]).not_to include("Bearer")
               body = JSON.parse(req.body)
               expect(body).not_to have_key("signature")
               expect(body).not_to have_key("apiVersion")
               expect(body).to include("amount" => 10_000, "currency" => "MVR")
               true
             end
             .to_return(json_response({ id: "txn_1", state: "PENDING" }, 201))

      transactions.create_v2(amount: 10_000, currency: "MVR")
      expect(stub).to have_been_requested
    end

    it "serializes tokenizationDetails as exactly the four documented keys, nested (T015)" do
      stub = stub_request(:post, v2_create_url(client)).with do |req|
        td = JSON.parse(req.body)["tokenizationDetails"]
        expect(td).to eq(
          "tokenize" => true, "paymentType" => "RECURRING",
          "recurringFrequency" => "MONTHLY", "expiryDate" => "2027-01-01"
        )
        true
      end.to_return(json_response({ id: "txn_1" }, 201))

      transactions.create_v2(
        amount: 10_000, currency: "MVR", customerId: "cus_1",
        tokenizationDetails: { tokenize: true, paymentType: "RECURRING",
                               recurringFrequency: "MONTHLY", expiryDate: "2027-01-01" }
      )
      expect(stub).to have_been_requested
    end

    it "maps a 201 body onto a TransactionRecord" do
      stub_request(:post, v2_create_url(client)).to_return(json_response({ id: "txn_1", merchantId: "m_1" }, 201))
      txn = transactions.create_v2(amount: 10_000, currency: "MVR")
      expect(txn.merchantId).to eq("m_1")
    end
  end

  describe "create_v2 is never auto-retried (FR-016 / SC-007)" do
    it "makes exactly ONE HTTP attempt on a timeout, then raises AvailabilityError" do
      stub = stub_request(:post, v2_create_url(client)).to_timeout
      expect { transactions.create_v2(amount: 10_000, currency: "MVR") }
        .to raise_error(BMLConnect::AvailabilityError)
      expect(stub).to have_been_requested.once
    end

    it "makes exactly ONE attempt on a 500 (does not retry server errors either)" do
      stub = stub_request(:post, v2_create_url(client)).to_return(json_response({ message: "boom" }, 500))
      expect { transactions.create_v2(amount: 10_000, currency: "MVR") }
        .to raise_error(BMLConnect::AvailabilityError)
      expect(stub).to have_been_requested.once
    end
  end

  describe "retrieve (FR-006)" do
    it "GETs /public/transactions/{id} and maps to a TransactionRecord" do
      stub = stub_request(:get, txn_url(client, "txn_1"))
             .to_return(json_response({ id: "txn_1", state: "CONFIRMED" }, 200))
      txn = transactions.retrieve("txn_1")
      expect(txn.state).to eq("CONFIRMED")
      expect(stub).to have_been_requested
    end

    it "maps 404 to NotFoundError" do
      stub_request(:get, txn_url(client, "missing")).to_return(json_response({ message: "no" }, 404))
      expect { transactions.retrieve("missing") }.to raise_error(BMLConnect::NotFoundError)
    end

    it "is not audited (read)" do
      stub_request(:get, txn_url(client, "txn_1")).to_return(json_response({ id: "txn_1" }, 200))
      transactions.retrieve("txn_1")
      expect(log_output).not_to include("retrieve")
    end
  end

  describe "update (FR-007)" do
    it "PATCHes only the supplied keys, no nulls" do
      stub = stub_request(:patch, txn_url(client, "txn_1")).with do |req|
        expect(JSON.parse(req.body)).to eq("customerReference" => "Basket 393")
        true
      end.to_return(json_response({ id: "txn_1" }, 200))

      transactions.update("txn_1", customerReference: "Basket 393")
      expect(stub).to have_been_requested
    end

    it "rejects an empty change set locally with no remote call" do
      expect { transactions.update("txn_1", {}) }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:changes) }
      expect(a_request(:patch, txn_url(client, "txn_1"))).not_to have_been_made
    end

    it "emits an update audit record (FR-017)" do
      stub_request(:patch, txn_url(client, "txn_1")).to_return(json_response({ id: "txn_1" }, 200))
      transactions.update("txn_1", pnr: "ABC123")
      expect(log_output).to include("update")
      expect(log_output).to include("txn_1")
    end
  end

  describe "capture (FR-008)" do
    it "POSTs id and amount to /capture and returns a TransactionRecord" do
      stub = stub_request(:post, txn_url(client, "txn_1", "/capture")).with do |req|
        expect(JSON.parse(req.body)).to eq("id" => "txn_1", "amount" => 10_000)
        true
      end.to_return(json_response({ id: "txn_1", state: "CONFIRMED" }, 200))

      transactions.capture("txn_1", amount: 10_000)
      expect(stub).to have_been_requested
    end

    it "applies the FR-005 amount rule (rejects a Float, no remote call)" do
      expect { transactions.capture("txn_1", amount: 100.0) }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:amount) }
      expect(a_request(:post, txn_url(client, "txn_1", "/capture"))).not_to have_been_made
    end

    it "is never auto-retried (money-moving)" do
      stub = stub_request(:post, txn_url(client, "txn_1", "/capture")).to_timeout
      expect { transactions.capture("txn_1", amount: 10_000) }.to raise_error(BMLConnect::AvailabilityError)
      expect(stub).to have_been_requested.once
    end

    it "emits a capture audit record" do
      stub_request(:post, txn_url(client, "txn_1", "/capture")).to_return(json_response({ id: "txn_1" }, 200))
      transactions.capture("txn_1", amount: 10_000)
      expect(log_output).to include("capture")
    end
  end

  describe "cancel (FR-009)" do
    it "POSTs to /cancel with no body and returns a TransactionRecord" do
      stub = stub_request(:post, txn_url(client, "txn_1", "/cancel"))
             .to_return(json_response({ id: "txn_1", state: "CANCELLED" }, 200))
      txn = transactions.cancel("txn_1")
      expect(txn.state).to eq("CANCELLED")
      expect(stub).to have_been_requested
    end

    it "emits a cancel audit record" do
      stub_request(:post, txn_url(client, "txn_1", "/cancel")).to_return(json_response({ id: "txn_1" }, 200))
      transactions.cancel("txn_1")
      expect(log_output).to include("cancel")
    end
  end
end
