# frozen_string_literal: true

require "spec_helper"

# T030 [US3] — FR-015/FR-016: every outcome audits, and the outcomes stay apart.
#
# Broader than the constitution's "state-changing operations" floor, on purpose:
# a rejected notification is the observable signature of a forgery attempt, and
# an operator needs to see it.
RSpec.describe BMLConnect::Webhooks, "audit trail" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }

  def handle_swallowing(**kwargs)
    webhooks.handle(**kwargs)
  rescue BMLConnect::Error
    nil
  end

  it "emits exactly one record for an accepted delivery" do
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
    webhooks.handle(body: json_body, headers: json_headers)

    expect(audit_records.size).to eq(1)
    record = last_audit_record
    expect(record["action"]).to eq("webhook_status_change")
    expect(record["outcome"]).to eq("success")
    expect(record["subject"]["transaction_id"]).to eq("txn_1")
    expect(record["at"]).to match(/\d{4}-\d{2}-\d{2}T/)
  end

  it "records the claimed status, the disagreement and the re-check flags" do
    delayed = build_webhook_client(recheck_delay: 3, log_io: @log_io)
    handler = delayed.webhooks
    allow(handler).to receive(:wait)
    stub_retrieve(delayed, "txn_1", transaction_body(state: "PENDING"), transaction_body(state: "PENDING"))

    handler.handle(body: json_body(transactionId: "txn_1", state: "PAID"), headers: json_headers)

    subject = last_audit_record["subject"]
    expect(subject["claimed_status"]).to eq("PAID")
    expect(subject["disagreed"]).to be(true)
    expect(subject["rechecked"]).to be(true)
    expect(subject["advisory_http_status"]).to eq(200)
  end

  # SC-009 enumerates the five cases that must each leave a record.
  describe "every outcome leaves a record (SC-009)" do
    it "audits a malformed delivery, distinguishably" do
      handle_swallowing(body: "garbage", headers: json_headers)

      record = last_audit_record
      expect(record["outcome"]).to eq("rejected")
      expect(record["subject"]["reason"]).to eq("malformed_body")
      expect(record["subject"]["advisory_http_status"]).to eq(400)
    end

    it "audits an unextractable identifier" do
      handle_swallowing(body: JSON.generate(state: "PAID"), headers: json_headers)

      expect(last_audit_record["subject"]["reason"]).to eq("no_transaction_id")
    end

    it "audits a secret rejection without either secret value" do
      secured = build_webhook_client(secret: "right")
      begin
        secured.webhooks.handle(body: json_body, headers: json_headers, presented_secret: "wrong")
      rescue BMLConnect::WebhookRejectedError # rubocop:disable Lint/SuppressedException
      end

      record = last_audit_record
      expect(record["outcome"]).to eq("rejected")
      expect(record["subject"]["reason"]).to eq("secret_mismatch")
      expect(webhook_log).not_to include("right")
      expect(webhook_log).not_to include("wrong")
    end

    it "audits a not-found transaction" do
      stub_retrieve_failure(client, "txn_1", status: 404)
      handle_swallowing(body: json_body, headers: json_headers)

      record = last_audit_record
      expect(record["subject"]["reason"]).to eq("not_found")
      expect(record["subject"]["transaction_id"]).to eq("txn_1")
    end

    it "audits an unreachable BML" do
      stub_retrieve_timeout(client)
      handle_swallowing(body: json_body, headers: json_headers)

      record = last_audit_record
      expect(record["subject"]["reason"]).to eq("unavailable")
      expect(record["subject"]["advisory_http_status"]).to eq(503)
    end
  end

  # FR-016 / US3-2: a rejection, an acceptance and a transport failure must not
  # look the same to an operator reading the trail.
  it "keeps the reasons mutually distinguishable" do
    reasons = []

    handle_swallowing(body: "garbage", headers: json_headers)
    reasons << last_audit_record["subject"]["reason"]

    stub_retrieve_timeout(client)
    handle_swallowing(body: json_body, headers: json_headers)
    reasons << last_audit_record["subject"]["reason"]

    WebMock.reset!
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
    webhooks.handle(body: json_body, headers: json_headers)
    reasons << last_audit_record["outcome"]

    expect(reasons.uniq.size).to eq(3)
  end

  # FR-004b: the raw body belongs in the masked audit record, not on the result.
  it "carries the raw body for forensics, scrubbed" do
    stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
    webhooks.handle(body: json_body(transactionId: "txn_1", state: "PAID", note: "keep-me"),
                    headers: json_headers)

    expect(last_audit_record["subject"]["body"]).to include("keep-me")
  end
end
