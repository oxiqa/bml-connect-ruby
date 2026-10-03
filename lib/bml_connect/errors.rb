# frozen_string_literal: true

module BMLConnect
  # Base error for the library. Reopened here (also declared in bml_connect.rb)
  # so this file is self-contained regardless of require order.
  class Error < StandardError
    # The HTTP status a host application SHOULD return to BML when this error
    # ends the handling of an inbound notification (feature 005, FR-016a).
    #
    # It is ADVICE, not control: the library never writes a response and does not
    # require the caller to honor it (FR-016b). The webhook path tags the error
    # object before it propagates; nil everywhere else, so no existing raise site
    # changes behavior. Carried on the base class rather than as a parallel
    # hierarchy of status-specific classes, which would have broken callers that
    # match on AvailabilityError.
    attr_accessor :advisory_http_status
  end

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

  # Raised when an inbound notification fails the optional shared-secret check
  # (feature 005, FR-009a). A DISTINCT class rather than a ValidationError with a
  # field, because FR-016/SC-008 require a failed secret check to be observably
  # distinguishable from a malformed body, and separating a security rejection
  # only by a `field:` value is too weak for something operators alert on.
  #
  # The secret gates SPEND, not trust: this error means no retrieve was spent, and
  # a matching secret never causes a payload to be believed (FR-009b).
  class WebhookRejectedError < Error; end

  # Raised when a value the caller asks for depends on a response field that is
  # not yet verified against a live BML environment. Specifically:
  # TransactionRecord#payment_url raises this when no hosted-payment-URL field is
  # present, rather than returning nil and sending a cardholder to a blank page
  # (contracts/bml-remote.md [UNVERIFIED] #1; research R7).
  class UnverifiedFieldError < Error; end
end
