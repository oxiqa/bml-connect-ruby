# frozen_string_literal: true

require "spec_helper"

# T005 [US1] — the remote HTTP contract for Customers#charge: the path derived
# from base_url, the raw Authorization header (no Bearer, no X-App-Id), the
# exact body, and the status->error mapping (FR-001, FR-009).
RSpec.describe "Customers#charge — remote contract" do
  let(:client) { build_client }
  let(:customers) { client.customers }
  let(:charge_url) { customers_url(client, "/charge") }

  def json(body, status, headers = {})
    { status: status, body: body.to_json,
      headers: { "Content-Type" => "application/json" }.merge(headers) }
  end

  def charge!
    customers.charge(customer_id: "cus_1", transaction_id: "txn_456", token_id: "tok_9")
  end

  it "POSTs to /public-customers/charge, a URL derived from the client base_url" do
    stub = stub_request(:post, charge_url).to_return(json({ id: "txn_456", state: "CONFIRMED" }, 200))
    charge!
    expect(stub).to have_been_requested.once
  end

  it "sends the raw Authorization key — no Bearer prefix, no X-App-Id header" do
    stub_request(:post, charge_url).to_return(json({ id: "txn_456", state: "CONFIRMED" }, 200))
    charge!

    expect(
      a_request(:post, charge_url).with do |req|
        req.headers["Authorization"] == "test-key" &&
          !req.headers["Authorization"].to_s.include?("Bearer") &&
          !req.headers.key?("X-App-Id")
      end
    ).to have_been_made
  end

  it "sends a body of exactly the three documented fields" do
    stub_request(:post, charge_url).to_return(json({ id: "txn_456", state: "CONFIRMED" }, 200))
    charge!

    expect(
      a_request(:post, charge_url).with do |req|
        JSON.parse(req.body).keys.sort == %w[customerId tokenId transactionId]
      end
    ).to have_been_made
  end

  describe "status -> error mapping (shared table)" do
    it "maps 400 to ValidationError" do
      stub_request(:post, charge_url).to_return(json({ message: "bad" }, 400))
      expect { charge! }.to raise_error(BMLConnect::ValidationError)
    end

    it "maps 401 to AuthenticationError" do
      stub_request(:post, charge_url).to_return(json({ message: "bad key" }, 401))
      expect { charge! }.to raise_error(BMLConnect::AuthenticationError)
    end

    it "maps 404 to NotFoundError" do
      stub_request(:post, charge_url).to_return(json({ message: "no such token" }, 404))
      expect { charge! }.to raise_error(BMLConnect::NotFoundError)
    end

    it "maps 429 to RateLimitError carrying Retry-After" do
      stub_request(:post, charge_url).to_return(json({ message: "slow down" }, 429, "Retry-After" => "30"))
      expect { charge! }
        .to raise_error(BMLConnect::RateLimitError) { |e| expect(e.retry_after).to eq("30") }
    end

    it "maps 5xx to AvailabilityError" do
      stub_request(:post, charge_url).to_return(json({ message: "down" }, 503))
      expect { charge! }.to raise_error(BMLConnect::AvailabilityError)
    end
  end
end
