# frozen_string_literal: true

require "spec_helper"

# T024 — enforce the ABSENCE of a create path (SC-006, FR-005/FR-008).
#
# The retired bml_tokenization gem shipped a fictional POST /tokens tokenize
# endpoint. This test fails the moment anyone reintroduces a fourth public
# method, so the absence is guarded by CI rather than by reviewer memory.
RSpec.describe BMLConnect::Tokens do
  it "exposes exactly list, retrieve, and delete — no create/tokenize/detokenize" do
    expect(described_class.public_instance_methods(false).sort).to eq(%i[delete list retrieve])
  end

  it "does not respond to any token-issuing or detokenizing operation" do
    client = build_client
    %i[create tokenize store detokenize card_number update].each do |forbidden|
      expect(client.tokens).not_to respond_to(forbidden)
    end
  end

  it "is reachable as client.tokens and memoized" do
    client = build_client
    expect(client.tokens).to be_a(described_class)
    expect(client.tokens).to equal(client.tokens)
  end

  # T025 — environment isolation (SC-004, FR-011). Deterministic routing check:
  # a production client hits the production host and never the UAT host, and a
  # sandbox client hits the UAT host and never production. Cross-environment
  # *token visibility* itself is a live observation, recorded during the UAT run
  # (contracts/bml-remote.md); this guards that the client can never send a
  # token request to the wrong environment.
  describe "environment isolation" do
    it "routes a production client's token requests to the production host only" do
      client = build_client(mode: "production")
      stub = stub_request(:get, tokens_url(client, "cus_1"))
             .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })
      client.tokens.list("cus_1")

      expect(stub).to have_been_requested
      expect(client.base_url).not_to include("uat")
      expect(a_request(:get, /uat/)).not_to have_been_made
    end

    it "routes a sandbox client's token requests to the UAT host only" do
      client = build_client(mode: "sandbox")
      stub = stub_request(:get, tokens_url(client, "cus_1"))
             .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })
      client.tokens.list("cus_1")

      expect(stub).to have_been_requested
      expect(client.base_url).to include("uat")
    end
  end
end
