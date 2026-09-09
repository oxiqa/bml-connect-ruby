# frozen_string_literal: true

require "spec_helper"

# T017 — the public surface is exactly what the platform offers: no combined
# create-and-charge method, and no `amount` on the charge (FR-003, SC-007). The
# charge schema carries no amount — the transaction governs it.
RSpec.describe BMLConnect::Customers, "public surface" do
  it "exposes exactly the documented methods — charge added, no create-and-charge combo" do
    expect(described_class.public_instance_methods(false).sort)
      .to eq(%i[archive charge create list retrieve update])
  end

  it "does not accept an `amount` keyword on #charge" do
    keywords = described_class.instance_method(:charge).parameters
                              .select { |type, _| %i[key keyreq].include?(type) }
                              .map { |_, name| name }

    expect(keywords).to contain_exactly(:customer_id, :transaction_id, :token_id, :actor)
    expect(keywords).not_to include(:amount)
  end

  it "exposes no method whose name suggests a combined create-and-charge" do
    combined = described_class.public_instance_methods(false)
                              .grep(/charge/)
                              .reject { |m| m == :charge }
    expect(combined).to be_empty
  end
end
