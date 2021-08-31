# frozen_string_literal: true
require 'faraday'

RSpec.describe BMLConnect::Client do
  let(:client) { BMLConnect::Client.new(api_key: "apikey", app_id: "app_id") }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:conn) { Faraday.new { |b| b.adapter(:test, stubs) } }

  it "has valid production endpoint" do
    expect(client.base_url).to eq(BMLConnect::Client::BML_PRODUCTION_ENDPOINT)
  end

  it "has valid sandbox endpoint" do
    test_client = BMLConnect::Client.new(api_key: "apiKey", app_id: "app_id", mode: "sandbox")
    expect(test_client.base_url).to eq(BMLConnect::Client::BML_SANDBOX_ENDPOINT)
  end

  it "has valid api_key" do
    expect(client.api_key).to eq("apikey")
  end

  it "should post data" do
    client.set_http_client(conn)
    stubs.post('/test') do |env|
      expect(env.url.path).to eq('/test')
      [
        200,
        { 'Content-Type': 'application/json' },
        {'status': 200}
      ]
    end
    resp = client.post('/test', {})
    expect(resp.env.method).to eq(:post) 
    stubs.verify_stubbed_calls
  end
end
