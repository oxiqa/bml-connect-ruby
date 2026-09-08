# frozen_string_literal: true

require "stringio"
require "uri"
require "logger"

# Shared helpers for the customers unit and contract specs.
module CustomersHelpers
  # A client wired for deterministic tests: a captured logger and zero retry
  # backoff so nothing sleeps. Uses the default (real) Faraday adapter so
  # WebMock can intercept.
  def build_client(mode: "sandbox", api_key: "test-key", app_id: "app-123", log_io: nil)
    @log_io = log_io || StringIO.new
    BMLConnect::Client.new(
      api_key: api_key,
      app_id: app_id,
      mode: mode,
      options: { logger: Logger.new(@log_io), retry_backoff: 0 }
    )
  end

  # The captured log output from the client built by build_client.
  def log_output
    @log_io ? @log_io.string : ""
  end

  # Full host-root URL for a customers path, derived from the client's base_url
  # exactly as the resource derives it (constitution/R10: no hardcoded host).
  def customers_url(client, suffix = "")
    URI.join(client.base_url, "/public-customers#{suffix}").to_s
  end
end

RSpec.configure do |config|
  config.include CustomersHelpers
end
