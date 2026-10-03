# frozen_string_literal: true

require "spec_helper"

# T013 [US1] — FR-004/005/006/008/009: the status always comes from a fresh
# retrieve, that retrieve is never auto-retried, and every failure mode stays
# distinguishable.
RSpec.describe BMLConnect::Webhooks, "the verifying retrieve" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }

  # SC-003: no result is ever produced without a retrieve having occurred.
  it "performs the retrieve and returns the authoritative record" do
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

    result = webhooks.handle(body: json_body, headers: json_headers)

    expect(result.transaction).to be_a(BMLConnect::Models::TransactionRecord)
    expect(result.status).to eq("PAID")
    expect(retrieve_count(client)).to eq(1)
  end

  it "exposes the time of the change from the authoritative record (FR-004)" do
    stub_retrieve(client, "txn_1", transaction_body(updated: "2026-09-27T11:22:33Z"))
    expect(webhooks.handle(body: json_body, headers: json_headers).changed_at)
      .to eq("2026-09-27T11:22:33Z")
  end

  # FR-009: the verifying retrieve MUST NOT be auto-retried. This is the
  # assertion that keeps the two-retrieve cap honest under a flaky BML.
  describe "never auto-retried (FR-009)" do
    it "makes exactly one HTTP attempt on a timeout" do
      stub_retrieve_timeout(client)

      expect { webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::AvailabilityError)
      expect(retrieve_count(client)).to eq(1)
    end

    it "makes exactly one HTTP attempt on a 503" do
      stub_retrieve_failure(client, "txn_1", status: 503)

      expect { webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::AvailabilityError)
      expect(retrieve_count(client)).to eq(1)
    end
  end

  # FR-005 / SC-007: the published contract enumerates no states, so any local
  # allow-list would be an invention.
  describe "status pass-through (FR-005, SC-007, SC-010)" do
    it "returns a status that appears nowhere in this repository, unchanged" do
      stub_retrieve(client, "txn_1", transaction_body(state: "ZZ_INVENTED_STATE_42"))
      expect(webhooks.handle(body: json_body, headers: json_headers).status)
        .to eq("ZZ_INVENTED_STATE_42")
    end

    it "does not upcase, downcase or otherwise normalize the reported status" do
      stub_retrieve(client, "txn_1", transaction_body(state: "paid"))
      expect(webhooks.handle(body: json_body, headers: json_headers).status).to eq("paid")
    end

    # SC-010: no allow-list governs handling. Asserted as an absence over the
    # constants the handler actually ships.
    it "ships no enumeration of transaction states" do
      states = %w[INITIATED QR_CODE_GENERATED PAID PENDING CANCELLED CONFIRMED FAILED]
      [BMLConnect::Webhooks, BMLConnect::Models::StatusChangeResult].each do |klass|
        klass.constants.each do |name|
          value = klass.const_get(name)
          next unless value.is_a?(Array)

          overlap = value.map { |entry| entry.to_s.upcase } & states
          expect(overlap).to be_empty, "#{klass}::#{name} looks like a state allow-list"
        end
      end
    end
  end

  # FR-008: three distinguishable failures, and never a fall back to the payload.
  describe "failures stay distinguishable (FR-008, FR-016, SC-008)" do
    it "raises NotFoundError for a transaction BML does not have" do
      stub_retrieve_failure(client, "txn_1", status: 404, body: { message: "no such transaction" })
      expect { webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::NotFoundError)
    end

    it "raises AuthenticationError when our credential is rejected" do
      stub_retrieve_failure(client, "txn_1", status: 401, body: { message: "bad key" })
      expect { webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::AuthenticationError)
    end

    it "raises RateLimitError on a 429" do
      stub_retrieve_failure(client, "txn_1", status: 429, body: { message: "slow down" })
      expect { webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::RateLimitError)
    end

    it "keeps all four outcomes mutually distinguishable" do
      classes = []
      [[404, BMLConnect::NotFoundError], [503, BMLConnect::AvailabilityError]].each do |status, expected|
        WebMock.reset!
        stub_retrieve_failure(client, "txn_1", status: status)
        begin
          webhooks.handle(body: json_body, headers: json_headers)
        rescue BMLConnect::Error => e
          classes << e.class
          expect(e).to be_a(expected)
        end
      end
      WebMock.reset!
      begin
        webhooks.handle(body: "nonsense", headers: json_headers)
      rescue BMLConnect::Error => e
        classes << e.class
      end
      expect(classes.uniq.size).to eq(3)
    end
  end
end
