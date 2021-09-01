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
      :is_preauthorization => false,
      :provider => 'visa',
      :redirect_url => 'https://lvh.me',
      :local_id => '0000',
      :customer_reference => 'C0000'
    }

    transaction = BMLConnect::Models::Transaction.new(data)
    expect(transaction.amount).to eq(data[:amount])
    expect(transaction.currency).to eq(data[:currency])
    expect(transaction.is_preauthorization).to eq(data[:is_preauthorization])
    expect(transaction.provider).to eq(data[:provider])
    expect(transaction.redirect_url).to eq(data[:redirect_url])
    expect(transaction.local_id).to eq(data[:local_id])
    expect(transaction.customer_reference).to eq(data[:customer_reference])
  end
end
