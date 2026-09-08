# frozen_string_literal: true

require "uri"

# Shared helpers for the tokens unit and contract specs. Reuses build_client
# from CustomersHelpers (loaded from the same support directory).
module TokensHelpers
  # Full host-root URL for a customer's tokens collection or a member path,
  # derived from the client's base_url exactly as the resource derives it
  # (constitution/R10: no hardcoded host).
  def tokens_url(client, customer_id, suffix = "")
    URI.join(client.base_url, "/public-customers/#{customer_id}/tokens#{suffix}").to_s
  end
end

RSpec.configure do |config|
  config.include TokensHelpers
end
