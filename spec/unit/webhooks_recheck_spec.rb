# frozen_string_literal: true

require "spec_helper"

# T014 [US1] — FR-010/010a/010b/010c/010d: one delayed re-check, and a hard cap
# that nothing in a payload can talk its way past.
#
# The delay is spent inside the CALLER's request, so no example here sleeps for
# real: the wait is stubbed and asserted (research R8).
RSpec.describe BMLConnect::Webhooks, "the re-check" do
  let(:disagreeing) { json_body(transactionId: "txn_1", state: "PAID") }

  describe "when the claim disagrees with the first retrieve" do
    let(:client) { build_webhook_client(recheck_delay: 3) }
    let(:webhooks) { client.webhooks }

    before { allow(webhooks).to receive(:wait) }

    it "waits the configured delay and retrieves exactly once more (SC-008a)" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"), transaction_body(state: "PAID"))

      result = webhooks.handle(body: disagreeing, headers: json_headers)

      expect(webhooks).to have_received(:wait).with(3).once
      expect(retrieve_count(client)).to eq(2)
      expect(result.status).to eq("PAID")
      expect(result).to be_rechecked
    end

    # FR-010d: a persistent disagreement is the expected shape of a replayed or
    # forged delivery, not a failure.
    it "reports the second retrieve even when it still disagrees, without raising" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"), transaction_body(state: "PENDING"))

      result = webhooks.handle(body: disagreeing, headers: json_headers)

      expect(result.status).to eq("PENDING")
      expect(result).to be_disagreed
      expect(result).to be_rechecked
      expect(retrieve_count(client)).to eq(2)
    end

    # FR-010a: no third call, no loop, no unbounded wait.
    it "never re-checks twice, however stubbornly the payload disagrees" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"), transaction_body(state: "PENDING"),
                    transaction_body(state: "PENDING"))

      webhooks.handle(body: disagreeing, headers: json_headers)

      expect(retrieve_count(client)).to eq(2)
      expect(webhooks).to have_received(:wait).once
    end

    it "does not re-check when the statuses agree" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

      result = webhooks.handle(body: disagreeing, headers: json_headers)

      expect(retrieve_count(client)).to eq(1)
      expect(result).not_to be_rechecked
      expect(result).not_to be_disagreed
      expect(webhooks).not_to have_received(:wait)
    end

    # Research R7: the two states observable in the published document are
    # uppercase. A callback spelling one of them differently would otherwise pay
    # the delay on every delivery for nothing.
    it "treats a case or whitespace difference as agreement, not disagreement" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))

      result = webhooks.handle(body: json_body(transactionId: "txn_1", state: " paid "),
                               headers: json_headers)

      expect(retrieve_count(client)).to eq(1)
      expect(result).not_to be_disagreed
      expect(webhooks).not_to have_received(:wait)
    end

    it "still reports the authoritative spelling, never the payload's (FR-005)" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      result = webhooks.handle(body: json_body(transactionId: "txn_1", state: "paid"),
                               headers: json_headers)
      expect(result.status).to eq("PAID")
      expect(result.claimed_status).to eq("paid")
    end
  end

  # SC-008b: with the delay at zero there is exactly one retrieve and no added
  # latency — the setting an endpoint under a tight deadline must use.
  describe "with the delay set to zero (FR-010b)" do
    let(:client) { build_webhook_client(recheck_delay: 0) }
    let(:webhooks) { client.webhooks }

    it "performs exactly one retrieve and never waits" do
      allow(webhooks).to receive(:wait)
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"))

      result = webhooks.handle(body: disagreeing, headers: json_headers)

      expect(retrieve_count(client)).to eq(1)
      expect(webhooks).not_to have_received(:wait)
      expect(result.status).to eq("PENDING")
    end

    # The disagreement is still recorded — it is the signature of a forgery
    # attempt or a stale replay, and an operator needs to see it.
    it "still reports the disagreement" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"))
      expect(webhooks.handle(body: disagreeing, headers: json_headers)).to be_disagreed
    end
  end

  # SC-008c / FR-010c: the published contract does not promise the payload
  # carries a status at all, so there is nothing to speculate on.
  describe "when the payload carries no comparable status" do
    let(:client) { build_webhook_client(recheck_delay: 3) }
    let(:webhooks) { client.webhooks }

    before { allow(webhooks).to receive(:wait) }

    it "performs exactly one retrieve and does not re-check speculatively" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"))

      result = webhooks.handle(body: json_body(transactionId: "txn_1"), headers: json_headers)

      expect(retrieve_count(client)).to eq(1)
      expect(result).not_to be_disagreed
      expect(result).not_to be_rechecked
      expect(webhooks).not_to have_received(:wait)
    end

    it "does not re-check when the claimed status is a non-string" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"))
      body = JSON.generate(transactionId: "txn_1", state: { weird: true })
      webhooks.handle(body: body, headers: json_headers)
      expect(retrieve_count(client)).to eq(1)
    end
  end

  # SC-008d: the cap holds across every inbound shape, not only the happy path.
  describe "the two-retrieve cap across every case (SC-008d)" do
    let(:client) { build_webhook_client(recheck_delay: 3) }
    let(:webhooks) { client.webhooks }

    before { allow(webhooks).to receive(:wait) }

    it "never exceeds two retrieves for malformed, forged, disagreeing or failing deliveries" do
      cases = [
        ["malformed", "not a body", 0],
        ["unextractable", JSON.generate(state: "PAID"), 0],
        ["disagreeing", JSON.generate(transactionId: "txn_1", state: "PAID"), 2]
      ]

      cases.each do |name, body, expected|
        WebMock.reset!
        stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"), transaction_body(state: "PENDING"))
        begin
          webhooks.handle(body: body, headers: json_headers)
        rescue BMLConnect::Error # rubocop:disable Lint/SuppressedException
        end
        expect(retrieve_count(client)).to eq(expected), "#{name} spent the wrong number of retrieves"
        expect(retrieve_count(client)).to be <= 2
      end
    end

    it "spends exactly one retrieve when the first one fails, never a re-check" do
      stub_retrieve_timeout(client)

      expect { webhooks.handle(body: disagreeing, headers: json_headers) }
        .to raise_error(BMLConnect::AvailabilityError)
      expect(retrieve_count(client)).to eq(1)
      expect(webhooks).not_to have_received(:wait)
    end
  end

  # The delay is configuration, and a bad value is a configuration error rather
  # than something to coerce into a plausible number.
  describe "delay validation" do
    it "rejects a negative delay before doing any work" do
      client = build_webhook_client(recheck_delay: -1)
      expect { client.webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::ValidationError) { |e|
          expect(e.field).to eq(:webhook_recheck_delay)
          expect(e.advisory_http_status).to eq(500)
        }
      expect_no_retrieve(client)
    end

    it "rejects a non-numeric delay rather than coercing it" do
      client = build_webhook_client(recheck_delay: "3")
      expect { client.webhooks.handle(body: json_body, headers: json_headers) }
        .to raise_error(BMLConnect::ValidationError) { |e|
          expect(e.field).to eq(:webhook_recheck_delay)
        }
    end

    it "accepts a fractional delay" do
      client = build_webhook_client(recheck_delay: 0.25)
      webhooks = client.webhooks
      allow(webhooks).to receive(:wait)
      stub_retrieve(client, "txn_1", transaction_body(state: "PENDING"), transaction_body(state: "PAID"))

      webhooks.handle(body: disagreeing, headers: json_headers)
      expect(webhooks).to have_received(:wait).with(0.25)
    end
  end
end
