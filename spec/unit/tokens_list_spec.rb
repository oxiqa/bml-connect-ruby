# frozen_string_literal: true

require "spec_helper"

# T009 [US1] — list validation, whitelisting, envelope handling, and the
# empty-vs-auth-failure distinction (research R6, FR-016).
RSpec.describe BMLConnect::Tokens, "#list" do
  let(:client) { build_client }
  let(:tokens) { client.tokens }
  let(:url) { tokens_url(client, "cus_1") }

  def json(body, status = 200, headers = {})
    { status: status, body: body.to_json,
      headers: { "Content-Type" => "application/json" }.merge(headers) }
  end

  def stub_list(body, status = 200)
    stub_request(:get, url).to_return(json(body, status))
  end

  it "rejects a blank customer_id without a remote call" do
    expect { tokens.list("  ") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
    expect(a_request(:get, %r{/public-customers})).not_to have_been_made
  end

  it "rejects a nil customer_id without a remote call" do
    expect { tokens.list(nil) }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
  end

  it "parses a { count, items } envelope" do
    stub_list(count: "2", items: [{ id: "tok_a" }, { id: "tok_b" }])
    list = tokens.list("cus_1")
    expect(list.count).to eq(2)
    expect(list.map(&:id)).to eq(%w[tok_a tok_b])
  end

  it "parses a bare array response (defensive, research R4)" do
    stub_list([{ id: "tok_a" }, { id: "tok_b" }])
    list = tokens.list("cus_1")
    expect(list.size).to eq(2)
    expect(list.count).to eq(2)
    expect(list.map(&:id)).to eq(%w[tok_a tok_b])
  end

  it "returns an empty list (not an error) for a customer with no stored cards" do
    stub_list(count: "0", items: [])
    list = tokens.list("cus_1")
    expect(list).to be_empty
    expect(list.count).to eq(0)
  end

  it "raises AuthenticationError on a 401 and never converts it to an empty list" do
    stub_list({ message: "bad key" }, 401)
    expect { tokens.list("cus_1") }.to raise_error(BMLConnect::AuthenticationError)
  end

  it "drops unknown keys, exposing only whitelisted fields" do
    stub_list(items: [{ id: "tok_1", brand: "VISA", sneaky: "5111111111111111",
                        paddedCardNumber: "411111******1111" }])
    token = tokens.list("cus_1").first
    expect(token.brand).to eq("VISA")
    expect(token.paddedCardNumber).to eq("411111******1111")
    expect(token).not_to respond_to(:sneaky)
    expect(token.to_h.keys).not_to include(:sneaky)
  end

  it "exposes #active as the non-deleted subset" do
    stub_list(items: [{ id: "tok_1", deleted: false }, { id: "tok_2", deleted: true }])
    list = tokens.list("cus_1")
    expect(list.active.map(&:id)).to eq(%w[tok_1])
  end

  it "rejects an actor that looks like a PAN, with no remote call" do
    expect { tokens.list("cus_1", actor: "4111 1111 1111 1111") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:actor) }
    expect(a_request(:get, %r{/public-customers})).not_to have_been_made
  end
end
