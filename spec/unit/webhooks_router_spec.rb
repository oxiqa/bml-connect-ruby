# frozen_string_literal: true

require "spec_helper"

RSpec.describe BMLConnect::Webhooks::Router do
  let(:router) { described_class.new }
  let(:result) { double("StatusChangeResult", transaction_id: "txn_1") }

  describe "resolving to a handler" do
    it "calls the handler the resolver names" do
      seen = nil
      router.resolve { |_r| :settlement }
      router.on(:enrolment) { raise "wrong handler" }
      router.on(:settlement) { |r| seen = r }

      router.dispatch(result)

      expect(seen).to be(result)
    end

    it "returns what the handler returned" do
      router.resolve { :settlement }
      router.on(:settlement) { :done }

      expect(router.dispatch(result)).to eq(:done)
    end

    it "accepts a string or symbol interchangeably" do
      seen = false
      router.resolve { "settlement" }
      router.on(:settlement) { seen = true }

      router.dispatch(result)

      expect(seen).to be(true)
    end
  end

  describe "a delivery nothing owns" do
    # A notification for a transaction this application did not create is
    # expected — the merchant's hook is global — but it must never vanish.
    it "falls through to the fallback" do
      seen = nil
      router.resolve { nil }
      router.otherwise { |r| seen = r }

      router.dispatch(result)

      expect(seen).to be(result)
    end

    it "raises when the resolver names a handler that was never registered" do
      router.resolve { :nobody }

      expect { router.dispatch(result) }
        .to raise_error(BMLConnect::Webhooks::Router::UnroutableError, /nobody/)
    end

    it "raises when nothing owns it and no fallback was registered" do
      router.resolve { nil }

      expect { router.dispatch(result) }
        .to raise_error(BMLConnect::Webhooks::Router::UnroutableError, /txn_1/)
    end
  end

  describe "building it" do
    it "refuses a resolver that was never set" do
      router.on(:settlement) { :done }

      expect { router.dispatch(result) }
        .to raise_error(BMLConnect::Webhooks::Router::UnroutableError, /resolver/)
    end

    it "refuses two handlers for one name, rather than silently replacing" do
      router.on(:settlement) { :first }

      expect { router.on(:settlement) { :second } }
        .to raise_error(ArgumentError, /settlement/)
    end

    it "refuses a handler with no block" do
      expect { router.on(:settlement) }.to raise_error(ArgumentError)
    end
  end
end

RSpec.describe "BMLConnect::Webhooks#handle with a router" do
  let(:client) { BMLConnect::Client.new(api_key: "k", mode: "sandbox") }
  let(:webhooks) { BMLConnect::Webhooks.new(client) }
  let(:record) { BMLConnect::Models::TransactionRecord.new(id: "txn_1", state: "CONFIRMED") }

  before do
    allow(client.transactions).to receive(:retrieve).and_return(record)
  end

  it "dispatches the verified result and returns what the handler returned" do
    seen = nil
    router = BMLConnect::Webhooks::Router.new
    router.resolve { :settlement }
    router.on(:settlement) { |r| seen = r; :handled }

    returned = webhooks.handle(body: '{"transactionId":"txn_1"}', router: router)

    expect(seen.transaction).to be(record)
    expect(returned).to eq(:handled)
  end

  it "returns the result unchanged when no router is given" do
    returned = webhooks.handle(body: '{"transactionId":"txn_1"}')

    expect(returned).to be_a(BMLConnect::Models::StatusChangeResult)
  end

  # The router must not become a way to trust the payload.
  it "still retrieves from the gateway before dispatching" do
    router = BMLConnect::Webhooks::Router.new
    router.resolve { :settlement }
    router.on(:settlement) { :handled }

    webhooks.handle(body: '{"transactionId":"txn_1","status":"CONFIRMED"}', router: router)

    expect(client.transactions).to have_received(:retrieve).with("txn_1", retries: false)
  end
end
