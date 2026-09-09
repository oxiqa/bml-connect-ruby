# frozen_string_literal: true

require "uri"

# Shared helpers for the transactions unit and contract specs. URLs are derived
# from the client's base_url exactly as the resource derives them (research R10:
# no hardcoded host), so a drift in an endpoint constant cannot be masked by a
# stale stub. `build_client` / `log_output` are provided by CustomersHelpers.
module TransactionsHelpers
  # Legacy v1 create / retrieve base: base_url already ends in "/public/", so the
  # relative "transactions" resolves under it.
  def v1_url(client, suffix = "")
    URI.join(client.base_url, "transactions#{suffix}").to_s
  end

  # Documented v2 create endpoint.
  def v2_create_url(client)
    URI.join(client.base_url, "/public/v2/transactions").to_s
  end

  # A /public/transactions/{id}[/capture|/cancel] URL.
  def txn_url(client, id, suffix = "")
    URI.join(client.base_url, "/public/transactions/#{id}#{suffix}").to_s
  end

  def json_response(body, status)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end
end

RSpec.configure do |config|
  config.include TransactionsHelpers

  # The v1 deprecation warning is process-wide (fires once). Reset before each
  # example so specs that assert on it start from a clean slate.
  config.before(:each) { BMLConnect::Transactions.v1_deprecation_warned = false }
end
