# frozen_string_literal: true

RSpec.describe BMLConnect::Models::Transaction do
  it "should raise `ArgumentError` exception" do
    expect {
      BMLConnect::Models::Transaction.new({})
    }.to raise_error(ArgumentError)
  end

  it "should initialize with valid properties" do
    data = {
      :amount => 1000,
      :currency => 'USD',
      :isPreauthorization => false,
      :provider => 'visa',
      :redirectUrl => 'https://lvh.me',
      :localId => '0000',
      :customerReference => 'C0000'
    }

    transaction = BMLConnect::Models::Transaction.new(data)
    expect(transaction.amount).to eq(data[:amount])
    expect(transaction.currency).to eq(data[:currency])
    expect(transaction.isPreauthorization).to eq(data[:isPreauthorization])
    expect(transaction.provider).to eq(data[:provider])
    expect(transaction.redirectUrl).to eq(data[:redirectUrl])
    expect(transaction.localId).to eq(data[:localId])
    expect(transaction.customerReference).to eq(data[:customerReference])
  end
end
