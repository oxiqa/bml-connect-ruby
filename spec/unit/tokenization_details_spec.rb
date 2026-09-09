# frozen_string_literal: true

require "spec_helper"

# T014 [US2] — every tokenizationDetails rule, one example each. Construction
# validates; no remote call is involved (this is a pure input object).
RSpec.describe BMLConnect::Models::TokenizationDetails do
  def build(fields, today: Date.new(2026, 9, 9))
    described_class.new(fields, today: today)
  end

  describe "required fields whenever tokenizationDetails is present" do
    it "requires tokenize" do
      expect { build(paymentType: "UNSCHEDULED") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:tokenize) }
    end

    it "requires tokenize to be boolean" do
      expect { build(tokenize: "yes", paymentType: "UNSCHEDULED") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:tokenize) }
    end

    it "requires paymentType" do
      expect { build(tokenize: true) }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:paymentType) }
    end

    it "rejects a paymentType outside the documented set" do
      expect { build(tokenize: true, paymentType: "WHENEVER") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:paymentType) }
    end

    it "accepts UNSCHEDULED with no extra fields" do
      expect { build(tokenize: true, paymentType: "UNSCHEDULED") }.not_to raise_error
    end
  end

  describe "conditional rules when paymentType is RECURRING" do
    it "requires recurringFrequency" do
      expect { build(tokenize: true, paymentType: "RECURRING", expiryDate: "2027-01-01") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:recurringFrequency) }
    end

    it "rejects a recurringFrequency outside the documented set" do
      expect { build(tokenize: true, paymentType: "RECURRING", recurringFrequency: "HOURLY", expiryDate: "2027-01-01") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:recurringFrequency) }
    end

    it "requires expiryDate" do
      expect { build(tokenize: true, paymentType: "RECURRING", recurringFrequency: "MONTHLY") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:expiryDate) }
    end

    it "accepts a valid RECURRING set" do
      expect {
        build(tokenize: true, paymentType: "RECURRING", recurringFrequency: "MONTHLY", expiryDate: "2027-01-01")
      }.not_to raise_error
    end
  end

  describe "expiryDate shape and future-date rule (FR-004)" do
    it "rejects a non yyyy-mm-dd form" do
      expect { build(tokenize: true, paymentType: "RECURRING", recurringFrequency: "MONTHLY", expiryDate: "01/01/2027") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:expiryDate) }
    end

    it "rejects an impossible calendar date" do
      expect { build(tokenize: true, paymentType: "RECURRING", recurringFrequency: "MONTHLY", expiryDate: "2027-02-30") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:expiryDate) }
    end

    it "rejects a date in the past" do
      expect { build(tokenize: true, paymentType: "RECURRING", recurringFrequency: "MONTHLY", expiryDate: "2020-01-01") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:expiryDate) }
    end

    it "validates expiryDate even for UNSCHEDULED when supplied" do
      expect { build(tokenize: true, paymentType: "UNSCHEDULED", expiryDate: "2020-01-01") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:expiryDate) }
    end
  end

  describe "#to_h serializes exactly the documented keys, omitting unset ones" do
    it "emits only the four documented keys" do
      td = build(tokenize: true, paymentType: "RECURRING", recurringFrequency: "MONTHLY", expiryDate: "2027-01-01")
      expect(td.to_h).to eq(
        tokenize: true, paymentType: "RECURRING", recurringFrequency: "MONTHLY", expiryDate: "2027-01-01"
      )
    end

    it "omits keys not supplied" do
      td = build(tokenize: true, paymentType: "UNSCHEDULED")
      expect(td.to_h).to eq(tokenize: true, paymentType: "UNSCHEDULED")
    end
  end
end
