# frozen_string_literal: true
require 'faraday'

RSpec.describe BMLConnect::Transactions do
  let(:client) { BMLConnect::Client.new(api_key: "apikey", app_id: "app_id") }
  let(:transactions) { BMLConnect::Transactions.new(client) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:conn) { Faraday.new { |b| b.adapter(:test, stubs) } }

  it "should have valid endpoint" do
    expect(BMLConnect::Transactions::END_POINT).to eq('transactions') 
  end

  it "should create a new transaction" do
    client.set_http_client(conn)
    stubs.post('/transactions') do |env|
      expect(env.url.path).to eq('/transactions')
      [
        200,
        { 'Content-Type': 'application/json' },
        {'status': 1}
      ]
    end
    data = {
      :amount => 1000,
      :currency => 'USD',
      :isPreauthorization => false,
      :provider => 'visa',
      :redirectUrl => 'https://lvh.me',
      :localId => '0000',
      :customerReference => 'C0000'
    }
    resp = transactions.create(data)
    expect(resp.env.status).to eq(200)
    stubs.verify_stubbed_calls
  end

  it "should return a transaction" do
    client.set_http_client(conn)
    stubs.get('/transactions/1') do |env|
      expect(env.url.path).to eq('/transactions/1')
      [
        200,
        { 'Content-Type': 'application/json' },
        {'status': 1}
      ]
    end
    resp = transactions.get(1)
    expect(resp.env.status).to eq(200)
    stubs.verify_stubbed_calls
  end

  it "should list transactions" do
    client.set_http_client(conn)
    stubs.get('/transactions') do |env|
      expect(env.url.path).to eq('/transactions')
      [
        200,
        { 'Content-Type': 'application/json' },
        {'status': 1}
      ]
    end
    resp = transactions.list({ page: 2 })
    expect(resp.env.status).to eq(200)
    stubs.verify_stubbed_calls
  end
end
