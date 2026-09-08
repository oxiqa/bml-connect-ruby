# frozen_string_literal: true

require "spec_helper"

# T014 [US2] — retrieve validation, whitelisting, and predicates.
RSpec.describe BMLConnect::Tokens, "#retrieve" do
  let(:client) { build_client }
  let(:tokens) { client.tokens }

  def json(body, status = 200)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def stub_get(body, status = 200)
    stub_request(:get, tokens_url(client, "cus_1", "/tok_1")).to_return(json(body, status))
  end

  it "rejects a blank customer_id without a remote call" do
    expect { tokens.retrieve("  ", "tok_1") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
    expect(a_request(:get, %r{/public-customers})).not_to have_been_made
  end

  it "rejects a blank token_id without a remote call" do
    expect { tokens.retrieve("cus_1", "  ") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:token_id) }
    expect(a_request(:get, %r{/public-customers})).not_to have_been_made
  end

  it "returns a whitelisted Token with its masked summary and predicates" do
    stub_get(id: "tok_1", brand: "VISA", paddedCardNumber: "411111******1111",
             tokenExpiryMonth: "11", tokenExpiryYear: "2030", deleted: false,
             tokenAgreementId: "agr_9", sneaky: "5111111111111111")
    token = tokens.retrieve("cus_1", "tok_1")

    expect(token.id).to eq("tok_1")
    expect(token.paddedCardNumber).to eq("411111******1111")
    expect(token.tokenExpiryMonth).to eq("11")
    expect(token.deleted?).to be(false)
    expect(token.recurring?).to be(true)
    expect(token).not_to respond_to(:sneaky)
  end

  it "reports #deleted? true when the token is soft-deleted" do
    stub_get(id: "tok_1", deleted: true)
    expect(tokens.retrieve("cus_1", "tok_1").deleted?).to be(true)
  end

  it "reports #recurring? false when no agreement id is present" do
    stub_get(id: "tok_1")
    expect(tokens.retrieve("cus_1", "tok_1").recurring?).to be(false)
  end
end
