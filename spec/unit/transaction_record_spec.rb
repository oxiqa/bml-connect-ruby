# frozen_string_literal: true

require "spec_helper"

# T008/T019 support — the value object's whitelist, payment-URL resolution, and
# the FR-015 guarantee that the hosted payment URL never leaks into to_h/inspect.
RSpec.describe BMLConnect::Models::TransactionRecord do
  describe "whitelisting" do
    it "pulls whitelisted attributes, symbol or string keys" do
      record = described_class.new("id" => "txn_1", state: "CONFIRMED", "paddedCardNumber" => "411111******1111")
      expect(record.id).to eq("txn_1")
      expect(record.state).to eq("CONFIRMED")
      expect(record.paddedCardNumber).to eq("411111******1111")
    end

    it "drops unexpected keys entirely" do
      record = described_class.new(id: "txn_1", cardNumber: "4111111111111111")
      expect(record.to_h).not_to have_key(:cardNumber)
      expect(record.inspect).not_to include("4111111111111111")
    end

    it "passes state through verbatim (never normalized, research R8)" do
      expect(described_class.new(state: "SOME_BML_STATE").state).to eq("SOME_BML_STATE")
    end
  end

  describe "#payment_url resolution order" do
    it "prefers the v1 `url` field" do
      record = described_class.new(url: "https://pay.bml/A", redirectUrl: "https://m/return")
      expect(record.payment_url).to eq("https://pay.bml/A")
    end

    it "falls back to redirectUrl, then qr.url" do
      expect(described_class.new(redirectUrl: "https://m/return").payment_url).to eq("https://m/return")
      expect(described_class.new(qr: { url: "https://pay.bml/qr" }).payment_url).to eq("https://pay.bml/qr")
    end

    it "RAISES UnverifiedFieldError when no candidate is present (never returns nil)" do
      expect { described_class.new(id: "txn_1").payment_url }
        .to raise_error(BMLConnect::UnverifiedFieldError)
    end
  end

  describe "the hosted payment URL is a completion secret (FR-015)" do
    let(:record) { described_class.new(id: "txn_1", url: "https://pay.bml/secret-xyz") }

    it "is omitted from #to_h" do
      expect(record.to_h).not_to have_key(:url)
      expect(record.to_h.values).not_to include("https://pay.bml/secret-xyz")
    end

    it "is omitted from #inspect" do
      expect(record.inspect).not_to include("secret-xyz")
    end

    it "is still reachable via the explicit accessor" do
      expect(record.payment_url).to eq("https://pay.bml/secret-xyz")
    end
  end

  describe "#tokenized?" do
    it "is true once a paymentToken is present" do
      expect(described_class.new(paymentToken: "tok_1").tokenized?).to be(true)
      expect(described_class.new(id: "txn_1").tokenized?).to be(false)
    end
  end
end
