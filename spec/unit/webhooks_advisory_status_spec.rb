# frozen_string_literal: true

require "spec_helper"

# T015 [US1] — FR-016a/016c/016d: every outcome carries an advisory status, and
# transient never gets confused with permanent.
#
# The advisory is ADVICE (FR-016b): the library never writes a response. It
# exists because the library is the only party that knows which failures are
# worth redelivering.
RSpec.describe BMLConnect::Webhooks, "advisory HTTP status" do
  let(:client) { build_webhook_client(secret: nil) }
  let(:webhooks) { client.webhooks }

  # The full mapping, enumerated. SC-008g requires every outcome covered.
  def advisory_for
    yield
    nil
  rescue BMLConnect::Error => e
    e.advisory_http_status
  end

  it "advises 200 on an accepted delivery" do
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
    expect(webhooks.handle(body: json_body, headers: json_headers).advisory_http_status).to eq(200)
  end

  it "advises a permanent 400 for a malformed body" do
    expect(advisory_for { webhooks.handle(body: "garbage", headers: json_headers) }).to eq(400)
  end

  it "advises a permanent 401 for a failed secret check" do
    secured = build_webhook_client(secret: "right")
    expect(advisory_for do
      secured.webhooks.handle(body: json_body, headers: json_headers, presented_secret: "wrong")
    end).to eq(401)
  end

  it "advises a permanent 422 for an unextractable identifier" do
    expect(advisory_for do
      webhooks.handle(body: JSON.generate(state: "PAID"), headers: json_headers)
    end).to eq(422)
  end

  # FR-016d / research R10: 404 from an HTTP endpoint reads as "no such
  # endpoint". A sender that decides the hook URL is gone may stop delivering,
  # so one forged identifier would become an outage for every genuine
  # notification after it. 422 says "received, unusable", which is the truth.
  it "advises a permanent 422 — never 404 — for a transaction BML does not have" do
    stub_retrieve_failure(client, "txn_1", status: 404)
    expect(advisory_for { webhooks.handle(body: json_body, headers: json_headers) }).to eq(422)
  end

  it "advises a transient 503 when BML is unreachable" do
    stub_retrieve_timeout(client)
    expect(advisory_for { webhooks.handle(body: json_body, headers: json_headers) }).to eq(503)
  end

  it "advises a transient 503 on a 5xx" do
    stub_retrieve_failure(client, "txn_1", status: 502)
    expect(advisory_for { webhooks.handle(body: json_body, headers: json_headers) }).to eq(503)
  end

  it "advises a transient 503 when rate limited" do
    stub_retrieve_failure(client, "txn_1", status: 429)
    expect(advisory_for { webhooks.handle(body: json_body, headers: json_headers) }).to eq(503)
  end

  # Our misconfiguration, not the sender's fault. Advising permanent would
  # discard genuine events for the whole duration of the mistake.
  it "advises a transient 503 when our own credential is rejected" do
    stub_retrieve_failure(client, "txn_1", status: 401)
    expect(advisory_for { webhooks.handle(body: json_body, headers: json_headers) }).to eq(503)
  end

  describe "SC-008h: the two kinds are never confused" do
    it "never advises 404 for any outcome" do
      advisories = []
      [[404, nil], [503, nil], [401, nil], [429, nil]].each do |status, _|
        WebMock.reset!
        stub_retrieve_failure(client, "txn_1", status: status)
        advisories << advisory_for { webhooks.handle(body: json_body, headers: json_headers) }
      end
      WebMock.reset!
      advisories << advisory_for { webhooks.handle(body: "garbage", headers: json_headers) }

      expect(advisories).not_to include(404)
    end

    it "advises transient for an unreachable BML and permanent for a broken delivery" do
      stub_retrieve_timeout(client)
      unreachable = advisory_for { webhooks.handle(body: json_body, headers: json_headers) }
      WebMock.reset!
      malformed = advisory_for { webhooks.handle(body: "garbage", headers: json_headers) }

      expect(unreachable).to be >= 500
      expect(malformed).to be_between(400, 499)
    end
  end

  # FR-016b: advice, not control.
  it "never writes or returns an HTTP response object" do
    forbidden = %i[respond render response write_response]
    expect(BMLConnect::Webhooks.public_instance_methods(false) & forbidden).to be_empty
  end
end
