# frozen_string_literal: true

require "spec_helper"

# T008 [US1] — create_v2 local validation, variant handling, amount rules, PAN
# screening, auditing, and payment-URL secrecy. Every rejection path asserts NO
# remote call was made.
RSpec.describe BMLConnect::Transactions, "#create_v2" do
  let(:client) { build_client }
  let(:transactions) { client.transactions }

  def stub_create(body: { id: "txn_1", state: "PENDING", redirectUrl: "https://m/return" }, status: 201)
    stub_request(:post, v2_create_url(client)).to_return(json_response(body, status))
  end

  def expect_no_remote_call
    expect(a_request(:post, v2_create_url(client))).not_to have_been_made
  end

  describe "amount rule (FR-005): positive Integer in minor units, never coerced" do
    it "rejects a missing amount, naming the field, with no remote call" do
      expect { transactions.create_v2(currency: "MVR") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:amount) }
      expect_no_remote_call
    end

    it "rejects a Float (100.0 is ambiguous)" do
      expect { transactions.create_v2(amount: 100.0, currency: "MVR") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:amount) }
      expect_no_remote_call
    end

    it "rejects a String amount" do
      expect { transactions.create_v2(amount: "10000", currency: "MVR") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:amount) }
      expect_no_remote_call
    end

    it "rejects zero" do
      expect { transactions.create_v2(amount: 0, currency: "MVR") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:amount) }
      expect_no_remote_call
    end

    it "rejects a negative amount" do
      expect { transactions.create_v2(amount: -100, currency: "MVR") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:amount) }
      expect_no_remote_call
    end

    it "accepts a positive Integer" do
      stub_create
      expect { transactions.create_v2(amount: 10_000, currency: "MVR") }.not_to raise_error
    end
  end

  describe "currency (FR-002)" do
    it "rejects a missing currency" do
      expect { transactions.create_v2(amount: 10_000) }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:currency) }
      expect_no_remote_call
    end
  end

  describe "unsupported variants (FR-020): rejected by name, not forwarded" do
    it "rejects a shop-order variant (order)" do
      expect { transactions.create_v2(amount: 10_000, currency: "MVR", order: { items: [] }) }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:order) }
      expect_no_remote_call
    end

    it "rejects a foreign-exchange variant (fxQuoteId)" do
      expect { transactions.create_v2(amount: 10_000, currency: "MVR", fxQuoteId: "fx_1") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:fxQuoteId) }
      expect_no_remote_call
    end
  end

  describe "customer variant (FR-020): variant 3 vs inline variant 4" do
    it "rejects supplying both customerId and inline customer" do
      expect {
        transactions.create_v2(amount: 10_000, currency: "MVR",
                               customerId: "cus_1", customer: { name: "A", email: "a@x.mv" })
      }.to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customerId) }
      expect_no_remote_call
    end

    it "rejects an inline customer missing email" do
      expect { transactions.create_v2(amount: 10_000, currency: "MVR", customer: { name: "A" }) }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer) }
      expect_no_remote_call
    end

    it "accepts variant 3 (customerId)" do
      stub_create
      expect { transactions.create_v2(amount: 10_000, currency: "MVR", customerId: "cus_1") }.not_to raise_error
    end

    it "accepts variant 4 (inline customer with name and email)" do
      stub_create
      expect {
        transactions.create_v2(amount: 10_000, currency: "MVR", customer: { name: "A", email: "a@x.mv" })
      }.not_to raise_error
    end
  end

  describe "PAN/CVV screening (FR-014): no field is exempt, incl. nested" do
    it "rejects a card number in customerReference before any remote call" do
      expect {
        transactions.create_v2(amount: 10_000, currency: "MVR", customerReference: "4111 1111 1111 1111")
      }.to raise_error(BMLConnect::ValidationError)
      expect_no_remote_call
    end

    it "rejects a card number hidden in the inline customer name" do
      expect {
        transactions.create_v2(amount: 10_000, currency: "MVR", customer: { name: "4111111111111111", email: "a@x.mv" })
      }.to raise_error(BMLConnect::ValidationError)
      expect_no_remote_call
    end

    it "rejects an actor reference that looks like a PAN" do
      expect { transactions.create_v2({ amount: 10_000, currency: "MVR" }, actor: "4111111111111111") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:actor) }
      expect_no_remote_call
    end
  end

  describe "success path" do
    it "returns a whitelisted TransactionRecord with id and state" do
      stub_create(body: { id: "txn_9", state: "PENDING" })
      txn = transactions.create_v2(amount: 10_000, currency: "MVR")
      expect(txn).to be_a(BMLConnect::Models::TransactionRecord)
      expect(txn.id).to eq("txn_9")
      expect(txn.state).to eq("PENDING")
    end

    it "emits a masked create audit line naming the transaction id and App ID" do
      stub_create(body: { id: "txn_9" })
      transactions.create_v2({ amount: 10_000, currency: "MVR" }, actor: "ops:jane")
      expect(log_output).to include("create")
      expect(log_output).to include("txn_9")
      expect(log_output).to include("app-123")
      expect(log_output).to include("ops:jane")
    end

    it "never lets the hosted payment URL reach the audit log (FR-015)" do
      stub_create(body: { id: "txn_9", url: "https://pay.bml/secret-abc" })
      transactions.create_v2({ amount: 10_000, currency: "MVR" }, actor: "ops:jane")
      expect(log_output).not_to include("secret-abc")
    end
  end

  describe "tokenization without a customer ([UNVERIFIED] #5): warn, do not block" do
    it "forwards the request and logs a warning rather than raising" do
      stub_create(body: { id: "txn_9" })
      expect {
        transactions.create_v2(amount: 10_000, currency: "MVR",
                               tokenizationDetails: { tokenize: true, paymentType: "UNSCHEDULED" })
      }.not_to raise_error
      expect(log_output).to include("without a customerId")
    end
  end
end

# T012 [US1] — the v1 create deprecation warning: fires once per process,
# leaves behavior and return type untouched.
RSpec.describe BMLConnect::Transactions, "v1 #create deprecation warning (FR-011)" do
  let(:client) { build_client }
  let(:transactions) { client.transactions }

  before { stub_request(:post, v1_url(client)).to_return(json_response({ id: "t1" }, 200)) }

  it "emits a single deprecation warning on first call" do
    transactions.create(amount: 1000, currency: "MVR")
    expect(log_output.scan("is deprecated").size).to eq(1)
  end

  it "does not warn again on a second call (deduplicated once per process)" do
    transactions.create(amount: 1000, currency: "MVR")
    transactions.create(amount: 1000, currency: "MVR")
    expect(log_output.scan("is deprecated").size).to eq(1)
  end

  it "still returns a Faraday::Response (warning does not change behavior)" do
    expect(transactions.create(amount: 1000, currency: "MVR")).to be_a(Faraday::Response)
  end
end
