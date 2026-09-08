# frozen_string_literal: true

require "spec_helper"

# T019 [US3] — delete returns true on 204, audits once (even across retries),
# validates ids, and screens the actor for card data (FR-013a x FR-014, R9).
RSpec.describe BMLConnect::Tokens, "#delete" do
  let(:client) { build_client }
  let(:tokens) { client.tokens }
  let(:url) { tokens_url(client, "cus_1", "/tok_1") }

  it "returns true on a 204 with no body" do
    stub_request(:delete, url).to_return(status: 204, body: "")
    expect(tokens.delete("cus_1", "tok_1")).to be(true)
  end

  it "rejects a blank customer_id without a remote call" do
    expect { tokens.delete("  ", "tok_1") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:customer_id) }
    expect(a_request(:delete, %r{/public-customers})).not_to have_been_made
  end

  it "rejects a blank token_id without a remote call" do
    expect { tokens.delete("cus_1", "  ") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:token_id) }
    expect(a_request(:delete, %r{/public-customers})).not_to have_been_made
  end

  it "rejects an actor that looks like a PAN, with no remote call" do
    expect { tokens.delete("cus_1", "tok_1", actor: "4111-1111-1111-1111") }
      .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:actor) }
    expect(a_request(:delete, %r{/public-customers})).not_to have_been_made
  end

  it "emits a masked audit log line naming the action, customer, and token" do
    stub_request(:delete, url).to_return(status: 204, body: "")
    tokens.delete("cus_1", "tok_1", actor: "ops:jane")
    expect(log_output).to include("delete")
    expect(log_output).to include("cus_1")
    expect(log_output).to include("tok_1")
    expect(log_output).to include("ops:jane")
  end

  it "emits exactly ONE audit record even when the delete is retried" do
    # First attempt a transient 503, then a 204: the shared transport retries,
    # and the audit must fire once, after the retry sequence settles.
    stub_request(:delete, url)
      .to_return(status: 503, body: { message: "upstream" }.to_json,
                 headers: { "Content-Type" => "application/json" })
      .to_return(status: 204, body: "")

    expect(tokens.delete("cus_1", "tok_1")).to be(true)
    expect(log_output.scan(/"action":"delete"/).size).to eq(1)
  end

  it "does not audit when the delete ultimately fails" do
    stub_request(:delete, url)
      .to_return(status: 404, body: { message: "gone" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    expect { tokens.delete("cus_1", "tok_1") }.to raise_error(BMLConnect::NotFoundError)
    expect(log_output).not_to include("\"action\":\"delete\"")
  end
end
