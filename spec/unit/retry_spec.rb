# frozen_string_literal: true

require "spec_helper"

# T007 — retry & backoff on transient failures (FR-013a, research R9).
#
# Exercised through the Tokens resource, but the behavior lives in the shared
# transport (BMLConnect::Resource#with_retries) and applies to every resource.
# build_client wires retry_backoff: 0 so nothing sleeps; max_retries defaults
# to 2 (so a request is attempted at most 3 times).
RSpec.describe "shared transport retry (FR-013a)" do
  let(:client) { build_client }
  let(:tokens) { client.tokens }
  let(:url) { tokens_url(client, "cus_1") }

  def json(body, status, headers = {})
    { status: status, body: body.to_json,
      headers: { "Content-Type" => "application/json" }.merge(headers) }
  end

  it "retries a 5xx then succeeds, returning the eventual result" do
    stub = stub_request(:get, url)
           .to_return(json({ message: "upstream" }, 503))
           .to_return(json({ count: "1", items: [{ id: "tok_1" }] }, 200))

    list = tokens.list("cus_1")

    expect(list.count).to eq(1)
    expect(stub).to have_been_requested.twice
  end

  it "retries a 408 request-timeout status then succeeds" do
    stub = stub_request(:get, url)
           .to_return(json({ message: "timeout" }, 408))
           .to_return(json([], 200))

    expect(tokens.list("cus_1")).to be_empty
    expect(stub).to have_been_requested.twice
  end

  it "retries a connection timeout then succeeds" do
    stub = stub_request(:get, url)
           .to_timeout
           .to_return(json([], 200))

    expect(tokens.list("cus_1")).to be_empty
    expect(stub).to have_been_requested.twice
  end

  it "retries a 429 up to the limit then raises RateLimitError carrying Retry-After" do
    stub = stub_request(:get, url).to_return(json({ message: "slow down" }, 429, "Retry-After" => "30"))

    expect { tokens.list("cus_1") }
      .to raise_error(BMLConnect::RateLimitError) { |e| expect(e.retry_after).to eq("30") }
    # 1 initial attempt + 2 retries (max_retries default)
    expect(stub).to have_been_requested.times(3)
  end

  it "raises AvailabilityError after exhausting retries on a persistent 5xx" do
    stub = stub_request(:get, url).to_return(json({ message: "down" }, 500))

    expect { tokens.list("cus_1") }.to raise_error(BMLConnect::AvailabilityError)
    expect(stub).to have_been_requested.times(3)
  end

  it "raises AvailabilityError after exhausting retries on a persistent timeout" do
    stub = stub_request(:get, url).to_timeout

    expect { tokens.list("cus_1") }.to raise_error(BMLConnect::AvailabilityError)
    expect(stub).to have_been_requested.times(3)
  end

  it "does NOT retry a non-transient error (404), making exactly one request" do
    stub = stub_request(:get, tokens_url(client, "cus_1", "/tok_x"))
           .to_return(json({ message: "no such token" }, 404))

    expect { tokens.retrieve("cus_1", "tok_x") }.to raise_error(BMLConnect::NotFoundError)
    expect(stub).to have_been_requested.once
  end

  it "does NOT retry a non-transient error (401 auth)" do
    stub = stub_request(:get, url).to_return(json({ message: "bad key" }, 401))

    expect { tokens.list("cus_1") }.to raise_error(BMLConnect::AuthenticationError)
    expect(stub).to have_been_requested.once
  end

  it "disables retry entirely when the client sets max_retries: 0" do
    no_retry = build_client
    no_retry.max_retries = 0
    stub = stub_request(:get, tokens_url(no_retry, "cus_1")).to_return(json({ message: "down" }, 500))

    expect { no_retry.tokens.list("cus_1") }.to raise_error(BMLConnect::AvailabilityError)
    expect(stub).to have_been_requested.once
  end
end
