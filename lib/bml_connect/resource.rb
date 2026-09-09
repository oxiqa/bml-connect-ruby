# frozen_string_literal: true

require "json"
require "uri"
require "faraday"

module BMLConnect
  # Shared transport base for the value-object resources (Customers, and the
  # token/charge resources that follow in features 002/004).
  #
  # Responsibilities: build the request URL from the client's base URL, dispatch
  # over the client's Faraday connection, apply bounded retry with backoff on
  # transient failures, and map HTTP status codes to the library error
  # hierarchy. Value-object construction, validation, and auditing live in the
  # concrete resource, not here.
  class Resource
    def initialize(client)
      @client = client
    end

    private

    attr_reader :client

    # Dispatch +method+ to +path+ (a host-root path like "/public-customers").
    # Returns the Faraday response on 2xx; raises a mapped error otherwise.
    #
    # +retries+ defaults to true (bounded retry with backoff on transient
    # failures). Pass +retries: false+ for money-moving calls that MUST make
    # exactly one attempt — transaction create and capture (FR-016): retry there
    # risks a double charge, and no server-side idempotency key is documented.
    def request(method, path, body: nil, retries: true)
      url = request_url(path)

      dispatch = lambda do
        client.http_client.public_send(method, url) do |req|
          req.body = JSON.generate(body) if body
        end
      end

      response = retries ? with_retries(&dispatch) : single_attempt(&dispatch)

      handle(response)
    end

    # Exactly one attempt, no retry. A transport failure becomes an
    # AvailabilityError immediately so the caller can reconcile rather than
    # blindly re-send (FR-016, SC-007).
    def single_attempt
      yield
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise AvailabilityError, e.message
    end

    # Customer paths live at the host root ("/public-customers"), NOT under the
    # "/public/" prefix the transaction endpoints use. URI.join with an absolute
    # path replaces base_url's path while keeping its scheme+host, so the URL is
    # still derived from the client (no hardcoded host) per constitution/R10.
    def request_url(path)
      URI.join(client.base_url, path).to_s
    end

    def handle(response)
      return response if (200..299).cover?(response.status)

      raise map_error(response)
    end

    def with_retries(&block)
      attempts = 0

      loop do
        begin
          response = block.call
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          raise AvailabilityError, e.message if attempts >= max_retries

          attempts += 1
          backoff(attempts)
          next
        end

        if retryable_status?(response.status) && attempts < max_retries
          attempts += 1
          backoff(attempts)
          next
        end

        return response
      end
    end

    # Transient statuses worth retrying (FR-013a): request timeout, rate limit,
    # and any 5xx. A 429 that survives the retries is still surfaced as a
    # RateLimitError by map_error, carrying BML's Retry-After hint for the
    # caller — the internal wait stays governed by the client's bounded backoff,
    # not by an arbitrary server-supplied delay.
    def retryable_status?(status)
      status == 408 || status == 429 || (500..599).cover?(status)
    end

    def backoff(attempts)
      seconds = retry_backoff * attempts
      sleep(seconds) if seconds.positive?
    end

    def max_retries
      client.respond_to?(:max_retries) && client.max_retries ? client.max_retries : 2
    end

    def retry_backoff
      value = client.respond_to?(:retry_backoff) ? client.retry_backoff : nil
      value.to_f
    end

    def map_error(response)
      status = response.status
      body = response.body
      message = extract_message(body) || "BML request failed with status #{status}"

      case status
      when 400, 422 then ValidationError.new(message)
      when 401, 403 then AuthenticationError.new(message)
      when 404      then NotFoundError.new(message)
      when 409      then ConflictError.new(message, body: body)
      when 429      then RateLimitError.new(message, retry_after: retry_after(response))
      else               AvailabilityError.new(message)
      end
    end

    def extract_message(body)
      return nil unless body.is_a?(Hash)

      body[:message] || body["message"] || body[:error] || body["error"]
    end

    def retry_after(response)
      headers = response.respond_to?(:headers) ? response.headers : nil
      headers && (headers["Retry-After"] || headers["retry-after"])
    end
  end
end
