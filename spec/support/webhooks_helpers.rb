# frozen_string_literal: true

require "json"
require "logger"
require "stringio"
require "uri"

# Shared helpers for the webhook-handler specs (feature 005).
#
# Every retrieve URL is derived from the client's base_url exactly as the
# resource derives it (constitution II/III: no hardcoded host), and nothing in
# these helpers sleeps — the re-check wait is stubbed, never spent (research R8).
module WebhooksHelpers
  PAN = "4111111111111111" # Luhn-valid, used to prove masking

  # A client wired for deterministic webhook specs. `recheck_delay: 0` by
  # default so the common case performs exactly one retrieve; specs that
  # exercise the re-check pass a positive delay and stub the wait.
  def build_webhook_client(secret: nil, recheck_delay: 0, log_io: nil)
    @log_io = log_io || StringIO.new
    BMLConnect::Client.new(
      api_key: "test-key",
      app_id: "app-123",
      mode: "sandbox",
      options: {
        logger: Logger.new(@log_io),
        retry_backoff: 0,
        webhook_secret: secret,
        webhook_recheck_delay: recheck_delay
      }
    )
  end

  def webhook_log
    @log_io ? @log_io.string : ""
  end

  # --- deliveries ---------------------------------------------------------

  def json_body(fields = { transactionId: "txn_1", state: "PAID" })
    JSON.generate(fields)
  end

  def form_body(fields = { transactionId: "txn_1", state: "PAID" })
    URI.encode_www_form(fields)
  end

  def json_headers
    { "Content-Type" => "application/json" }
  end

  def form_headers
    { "Content-Type" => "application/x-www-form-urlencoded" }
  end

  # A Rack-style env: Content-Type lives under CONTENT_TYPE, other headers are
  # HTTP_-prefixed, and unrelated keys are present — exactly what an integrator
  # passing `request.env` hands us.
  def rack_env(content_type: "application/json")
    {
      "CONTENT_TYPE" => content_type,
      "HTTP_USER_AGENT" => "BML",
      "REQUEST_METHOD" => "POST",
      "rack.url_scheme" => "https"
    }
  end

  # --- the authoritative retrieve ----------------------------------------

  def transaction_body(id: "txn_1", state: "PENDING", updated: "2026-09-27T10:00:00Z")
    { id: id, state: state, updated: updated, amount: 10_000, currency: "MVR" }
  end

  # Stub GET /public/transactions/{id}. Pass several bodies to script a
  # sequence (first retrieve, then the re-check).
  #
  # Deliberately keyword-free: on Ruby 2.7 a trailing Hash positional would be
  # converted into keyword arguments, so a `status:` kwarg here would swallow the
  # response body. Non-2xx responses go through stub_retrieve_failure.
  def stub_retrieve(client, id = "txn_1", *bodies)
    bodies = [transaction_body(id: id)] if bodies.empty?
    responses = bodies.map { |body| json_response(body, 200) }
    stub_request(:get, txn_url(client, id)).to_return(*responses)
  end

  def stub_retrieve_failure(client, id = "txn_1", status: 503, body: { message: "upstream" })
    stub_request(:get, txn_url(client, id)).to_return(json_response(body, status))
  end

  def stub_retrieve_timeout(client, id = "txn_1")
    stub_request(:get, txn_url(client, id)).to_timeout
  end

  # How many HTTP retrieves were actually spent. This is the number FR-009 caps
  # at two — it counts HTTP calls, not logical operations.
  def retrieve_count(client, id = "txn_1")
    WebMock::RequestRegistry.instance.times_executed(
      WebMock::RequestPattern.new(:get, txn_url(client, id))
    )
  end

  def expect_no_retrieve(client, id = "txn_1")
    expect(retrieve_count(client, id)).to eq(0)
  end

  # The last audit line the client's logger captured, parsed back to a hash.
  def last_audit_record
    line = webhook_log.lines.grep(/"action"/).last
    return nil unless line

    JSON.parse(line[/\{.*\}/m])
  end

  def audit_records
    webhook_log.lines.grep(/"action"/).map { |line| JSON.parse(line[/\{.*\}/m]) }
  end
end

RSpec.configure do |config|
  config.include WebhooksHelpers
end
