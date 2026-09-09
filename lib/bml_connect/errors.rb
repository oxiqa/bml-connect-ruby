# frozen_string_literal: true

module BMLConnect
  # Base error for the library. Reopened here (also declared in bml_connect.rb)
  # so this file is self-contained regardless of require order.
  class Error < StandardError; end

  # Raised for local validation failures (before any remote call) and for
  # BML 400/422 responses. Carries the offending field where known.
  class ValidationError < Error
    attr_reader :field

    def initialize(message = nil, field: nil)
      @field = field
      super(message)
    end
  end

  # 401/403 — missing, invalid, or unprovisioned credentials.
  class AuthenticationError < Error; end

  # 404 — no customer matches the given id.
  class NotFoundError < Error; end

  # 409 — conflicting state. Carries the parsed response body for inspection.
  class ConflictError < Error
    attr_reader :body

    def initialize(message = nil, body: nil)
      @body = body
      super(message)
    end
  end

  # 429 — rate limited. Carries the Retry-After hint when BML supplies one.
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      @retry_after = retry_after
      super(message)
    end
  end

  # Timeout, connection failure, 408, or 5xx after bounded retries. Distinct
  # from every other error so callers can safely retry later.
  class AvailabilityError < Error; end

  # Raised when a value the caller asks for depends on a response field that is
  # not yet verified against a live BML environment. Specifically:
  # TransactionRecord#payment_url raises this when no hosted-payment-URL field is
  # present, rather than returning nil and sending a cardholder to a blank page
  # (contracts/bml-remote.md [UNVERIFIED] #1; research R7).
  class UnverifiedFieldError < Error; end
end
