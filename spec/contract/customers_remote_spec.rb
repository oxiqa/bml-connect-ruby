# frozen_string_literal: true

require "spec_helper"

# T014/T018/T022/T026/T030 — the remote HTTP contract for every operation.
# Every stub URL is derived from client.base_url (research R10): no host is
# hardcoded, so a drift in the client's endpoint constant can never be masked
# by a stale stub.
RSpec.describe BMLConnect::Customers, "remote contract" do
  let(:client) { build_client }
  let(:customers) { client.customers }

  def json(body, status)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  describe "auth + create request shape" do
    it "POSTs to /public-customers with the raw Authorization header, no Bearer, no X-App-Id" do
      stub = stub_request(:post, customers_url(client))
             .with(headers: { "Authorization" => "test-key" }) do |req|
               expect(req.headers).not_to have_key("X-App-Id")
               expect(req.headers["Authorization"]).not_to include("Bearer")
               body = JSON.parse(req.body)
               expect(body).to eq("name" => "Aisha Ali", "email" => "aisha@example.mv", "billingCity" => "Male")
               true
             end
             .to_return(json({ id: "cus_1", name: "Aisha Ali", email: "aisha@example.mv" }, 201))

      customer = customers.create(name: "Aisha Ali", email: "aisha@example.mv", billingCity: "Male")
      expect(customer.id).to eq("cus_1")
      expect(stub).to have_been_requested
    end

    it "maps a 201 body onto a whitelisted Customer" do
      stub_request(:post, customers_url(client))
        .to_return(json({ id: "cus_1", companyId: "co_9", currency: "MVR" }, 201))
      customer = customers.create(name: "Aisha", email: "aisha@example.mv")
      expect(customer.companyId).to eq("co_9")
      expect(customer.currency).to eq("MVR")
    end
  end

  describe "retrieve" do
    it "GETs /public-customers/{id}" do
      stub = stub_request(:get, customers_url(client, "/cus_1"))
             .to_return(json({ id: "cus_1" }, 200))
      customers.retrieve("cus_1")
      expect(stub).to have_been_requested
    end

    it "maps 404 to NotFoundError" do
      stub_request(:get, customers_url(client, "/missing"))
        .to_return(json({ message: "not found" }, 404))
      expect { customers.retrieve("missing") }.to raise_error(BMLConnect::NotFoundError)
    end
  end

  describe "list" do
    it "GETs /public-customers with no query string and maps the envelope" do
      stub = stub_request(:get, customers_url(client))
             .to_return(json({ count: "1", items: [{ id: "cus_1" }] }, 200))
      list = customers.list
      expect(list.count).to eq(1)
      expect(stub).to have_been_requested
    end
  end

  describe "update" do
    it "uses PATCH (not PUT)" do
      stub = stub_request(:patch, customers_url(client, "/cus_1"))
             .to_return(json({ id: "cus_1" }, 200))
      customers.update("cus_1", billingCity: "Hulhumale")
      expect(stub).to have_been_requested
      expect(a_request(:put, customers_url(client, "/cus_1"))).not_to have_been_made
    end

    it "maps 404 to NotFoundError" do
      stub_request(:patch, customers_url(client, "/missing"))
        .to_return(json({ message: "not found" }, 404))
      expect { customers.update("missing", billingCity: "X") }.to raise_error(BMLConnect::NotFoundError)
    end
  end

  describe "archive" do
    it "DELETEs /public-customers/{id} and treats 204 as success" do
      stub = stub_request(:delete, customers_url(client, "/cus_1")).to_return(status: 204, body: "")
      expect(customers.archive("cus_1")).to be(true)
      expect(stub).to have_been_requested
    end

    it "maps 400 to ValidationError" do
      stub_request(:delete, customers_url(client, "/cus_1")).to_return(json({ message: "bad" }, 400))
      expect { customers.archive("cus_1") }.to raise_error(BMLConnect::ValidationError)
    end
  end

  describe "error mapping" do
    {
      400 => BMLConnect::ValidationError,
      401 => BMLConnect::AuthenticationError,
      403 => BMLConnect::AuthenticationError,
      404 => BMLConnect::NotFoundError,
      409 => BMLConnect::ConflictError,
      429 => BMLConnect::RateLimitError,
      500 => BMLConnect::AvailabilityError
    }.each do |status, error|
      it "maps #{status} to #{error}" do
        stub_request(:get, customers_url(client, "/cus_1"))
          .to_return(json({ message: "err" }, status))
        expect { customers.retrieve("cus_1") }.to raise_error(error)
      end
    end

    it "raises AvailabilityError on a connection failure" do
      stub_request(:get, customers_url(client, "/cus_1")).to_raise(Faraday::ConnectionFailed.new("boom"))
      expect { customers.retrieve("cus_1") }.to raise_error(BMLConnect::AvailabilityError)
    end

    it "carries Retry-After on a 429" do
      stub_request(:get, customers_url(client, "/cus_1"))
        .to_return(status: 429, body: {}.to_json, headers: { "Content-Type" => "application/json",
                                                             "Retry-After" => "30" })
      expect { customers.retrieve("cus_1") }
        .to raise_error(BMLConnect::RateLimitError) { |e| expect(e.retry_after).to eq("30") }
    end
  end
end
