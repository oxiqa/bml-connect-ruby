# frozen_string_literal: true

require "digest"
require "json"
require "uri"

module BMLConnect
  # Handles an inbound BML transaction-status notification (feature 005).
  #
  # == The trust model, in one paragraph
  #
  # +reference/Connect-API.json+ documents how a merchant REGISTERS a hook and
  # nothing whatsoever about the notification it produces — not the HTTP method,
  # not the payload, and above all no signature, secret, or authentication. The
  # entire inbound surface is therefore [UNVERIFIED], and this handler is built to
  # need almost nothing from it: the payload is an untrusted HINT that something
  # changed, and every consequential fact comes from re-retrieving the transaction
  # from BML (FR-006). A forged "payment confirmed" can at worst cost one wasted
  # retrieve. There is no mode, option, or flag that reports a payload's own
  # claims as fact (FR-007) — see spec/unit/webhooks_surface_spec.rb, which
  # asserts the switch does not exist to be found.
  #
  # == Deliberately not a Resource
  #
  # This class issues no HTTP of its own: the verifying retrieve is delegated to
  # +client.transactions.retrieve+, so the library has exactly one implementation
  # of a transaction read and this path inherits its status-to-error mapping. It
  # also avoids a real collision — +Resource#handle(response)+ is private, and a
  # subclass defining a public +#handle(body:, ...)+ would be called with a Faraday
  # response and blow up.
  #
  # == What it costs
  #
  # At most TWO retrieves per notification, neither auto-retried (FR-009): the
  # verify, plus at most one delayed re-check when the payload's claimed status
  # disagrees (FR-010). Nothing a payload says can produce a third.
  #
  # == The optional shared secret gates SPEND, not trust
  #
  # When +webhook_secret+ is configured, a delivery whose presented value is absent
  # or wrong is rejected before any retrieve is spent (FR-009a). A matching secret
  # never causes the payload to be believed and never skips the retrieve (FR-009b).
  # The library does NOT infer where the secret travels — no default header, query
  # parameter, or path segment, and it never asks for the request URL (FR-009e).
  # BML chooses the callback's headers, so in practice a secret can only ride in the
  # URL the merchant registered; extracting it is the caller's job, comparing it is
  # this class's.
  class Webhooks
    # Candidate field names for the transaction identifier, in resolution order.
    # ALL [UNVERIFIED] until a real delivery is observed (FR-002a, SC-011).
    #
    # * +transactionId+ — the exact spelling BML uses wherever this value IS
    #   documented: the path parameter of +/public/transactions/{transactionId}+
    #   and the +transactionId+ field of the charge body. The strongest inference
    #   available from the published document.
    # * +transaction_id+ — the snake_case spelling of the same name, for a callback
    #   emitted by a different service than the REST API.
    # * +id+ — the field name on the +Transaction+ schema itself, for a payload
    #   that embeds a record rather than naming one.
    #
    # Top-level keys only, and only a non-blank String counts. A nested payload is
    # what +extract_id:+ is for; walking arbitrary nesting would mean inventing a
    # search strategy over a document that describes no payload at all.
    #
    # +localId+ is deliberately ABSENT: it is the merchant's own reference, not
    # BML's transaction id, so retrieving by it would 404 onto the permanent
    # advisory path. A plausible-looking candidate that produces a confidently
    # wrong outcome is worse than no candidate.
    ID_CANDIDATES = %i[transactionId transaction_id id].freeze

    # Candidate field names for the payload's CLAIMED status, in resolution order.
    # Both [UNVERIFIED]. Read solely for the FR-010 disagreement comparison and
    # never reported as fact. +state+ is the +Transaction+ schema's spelling;
    # +status+ is the common alternative in callback payloads generally.
    STATUS_CANDIDATES = %i[state status].freeze

    FORM_MEDIA_TYPE = "application/x-www-form-urlencoded"
    JSON_MEDIA_TYPE = "application/json"

    # Advisory HTTP statuses (FR-016a). Advice only: this class never writes a
    # response (FR-016b). The full mapping and its reasoning live in
    # specs/005-webhook-handler/contracts/library-api.md.
    ADVISORY_ACCEPTED = 200 # handled; an authoritative record was returned
    ADVISORY_MALFORMED = 400 # permanent: unparseable body, do not redeliver
    ADVISORY_REJECTED = 401 # permanent: secret absent or wrong
    ADVISORY_UNUSABLE = 422 # permanent: received, but nothing usable in it
    ADVISORY_UNEXPECTED = 500 # transient: our bug or our misconfiguration
    ADVISORY_TRANSIENT = 503 # transient: please redeliver

    def initialize(client)
      @client = client
    end

    # Handle one inbound notification and return a Models::StatusChangeResult.
    #
    # +body+::             the raw request body (String)
    # +headers+::          the delivery's headers; a Rails +request.headers+, a
    #                      Rack +request.env+, or a plain hash all work
    # +presented_secret+:: the secret value YOU extracted from the delivery,
    #                      required only when +webhook_secret+ is configured
    #                      (FR-009a). The library never guesses its location.
    # +extract_id+::       a callable overriding the built-in candidate list
    #                      OUTRIGHT (FR-002b). Receives +(payload, headers)+ —
    #                      headers included so an identifier arriving outside the
    #                      body does not block you (FR-002c) — and returns the
    #                      identifier or nil for "not found".
    # +actor+::            who or what is handling, for the audit record's +who+.
    #
    # The reported status ALWAYS comes from a fresh retrieve. Raises on every
    # outcome other than success; every error carries +advisory_http_status+.
    #
    # Ordering note: the secret check runs BEFORE parsing, not merely before the
    # retrieve FR-009a requires. An unauthenticated sender should not be able to
    # reach the parser at all, since the library enforces no body size limit
    # (FR-003c) and parsing is the only work left that an attacker can provoke.
    def handle(body:, headers: {}, presented_secret: nil, extract_id: nil, actor: nil)
      screen_actor!(actor)
      delay = recheck_delay!(actor: actor, raw_body: body)
      normalized = normalize_headers(headers)

      verify_secret!(presented_secret, actor: actor, raw_body: body)
      payload = parse_body!(body, normalized, actor: actor)
      transaction_id = extract_identifier!(payload, normalized, extract_id, actor: actor, raw_body: body)
      claimed = first_string(payload, STATUS_CANDIDATES)

      record = retrieve!(transaction_id, actor: actor, raw_body: body, claimed: claimed)
      rechecked = false

      if disagreement?(claimed, record.state) && delay.positive?
        wait(delay)
        record = retrieve!(transaction_id, actor: actor, raw_body: body, claimed: claimed)
        rechecked = true
      end

      build_result(transaction_id, record, claimed, rechecked).tap do |result|
        audit(:success, actor: actor, raw_body: body, result: result)
      end
    end

    private

    attr_reader :client

    # --- the wait ----------------------------------------------------------

    # The single re-check delay, spent synchronously inside the CALLER's request
    # (FR-010b). Isolated in one method so specs can observe it without any test
    # ever sleeping for real.
    def wait(seconds)
      sleep(seconds)
    end

    # --- configuration -----------------------------------------------------

    # Validated, never coerced: a delay we guessed at would be a silent behavior
    # change on a latency-sensitive path.
    def recheck_delay!(actor:, raw_body:)
      value = client.respond_to?(:webhook_recheck_delay) ? client.webhook_recheck_delay : nil
      value = Client::DEFAULT_WEBHOOK_RECHECK_DELAY if value.nil?

      unless value.is_a?(Numeric) && !value.negative?
        error = ValidationError.new(
          "webhook_recheck_delay must be a non-negative number of seconds, got #{value.inspect}",
          field: :webhook_recheck_delay
        )
        # Our misconfiguration, not the sender's fault, so advise transient: a
        # redelivery after an operator fixes the setting should succeed.
        reject!(error, ADVISORY_UNEXPECTED, reason: :configuration, actor: actor,
                                            raw_body: raw_body)
      end

      value
    end

    def configured_secret
      client.respond_to?(:webhook_secret) ? client.webhook_secret : nil
    end

    # --- the secret --------------------------------------------------------

    def verify_secret!(presented, actor:, raw_body:)
      secret = configured_secret
      return if blank?(secret)

      return if !blank?(presented) && secure_equal?(secret, presented)

      # Neither value appears in the message (FR-012).
      reject!(
        WebhookRejectedError.new("inbound notification did not present a matching shared secret"),
        ADVISORY_REJECTED, reason: :secret_mismatch, actor: actor, raw_body: raw_body
      )
    end

    # Constant-time comparison (FR-009d). OpenSSL.fixed_length_secure_compare is
    # unavailable on this toolchain (verified on Ruby 2.7.4) and Rack::Utils is out
    # of reach (FR-001 forbids the dependency), so both operands are digested to a
    # fixed 32 bytes and XOR-accumulated over every byte. Digesting first means
    # neither the loop count nor the comparison time leaks the secret's length —
    # the weakness a naive length check introduces.
    def secure_equal?(expected, presented)
      left = Digest::SHA256.digest(expected.to_s)
      right = Digest::SHA256.digest(presented.to_s)

      difference = 0
      left.bytesize.times { |index| difference |= left.getbyte(index) ^ right.getbyte(index) }
      difference.zero?
    end

    # --- parsing -----------------------------------------------------------

    # Two formats, selected by declared Content-Type, with a documented fallback
    # (FR-003a). No size or nesting limit is enforced (FR-003c): the library does
    # not own the socket, so bounding the request is the host application's job.
    def parse_body!(body, headers, actor:)
      raw = body.to_s
      malformed!("notification body is empty", actor: actor, raw_body: body) if raw.strip.empty?

      unless raw.dup.force_encoding(Encoding::UTF_8).valid_encoding?
        malformed!("notification body is not valid UTF-8", actor: actor, raw_body: body)
      end

      parsed = parse_by_media_type(raw, headers["content-type"])

      unless parsed.is_a?(Hash)
        malformed!(
          "notification body could not be parsed as JSON or form-encoded data",
          actor: actor, raw_body: body
        )
      end

      deep_symbolize(parsed)
    end

    def parse_by_media_type(raw, content_type)
      media = media_type(content_type)

      if json_media?(media)
        try_json(raw)
      elsif media == FORM_MEDIA_TYPE
        try_form(raw)
      else
        # Documented order, and the order matters: URI.decode_www_form does NOT
        # raise on a JSON body — it returns one garbage key holding the whole
        # string — so trying form first would mask every JSON payload instead of
        # failing. JSON.parse, by contrast, raises cleanly on a form body.
        try_json(raw) || try_form(raw)
      end
    end

    def media_type(content_type)
      content_type.to_s.split(";").first.to_s.strip.downcase
    end

    def json_media?(media)
      media == JSON_MEDIA_TYPE || media.end_with?("+json")
    end

    def try_json(raw)
      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    # A form body always contains "=" if it carries any field at all. Requiring it
    # stops "hello world" from becoming {"hello world" => ""} — decode_www_form is
    # permissive enough to "succeed" on arbitrary text.
    def try_form(raw)
      return nil unless raw.include?("=")

      pairs = URI.decode_www_form(raw)
      return nil if pairs.empty? || pairs.any? { |key, _| key.to_s.strip.empty? }

      pairs.to_h
    rescue ArgumentError
      nil
    end

    # --- headers -----------------------------------------------------------

    # Normalized once so Content-Type resolves whether the caller passed
    # "Content-Type", "content_type", "CONTENT_TYPE", or Rack's
    # "HTTP_CONTENT_TYPE" (research R5). First key wins on collision; a collision
    # is not an error.
    def normalize_headers(headers)
      return {} unless headers.respond_to?(:each_pair)

      headers.each_pair.each_with_object({}) do |(key, value), out|
        name = key.to_s.downcase.tr("_", "-").sub(/\Ahttp-/, "")
        out[name] = value unless out.key?(name)
      end
    end

    # --- extraction --------------------------------------------------------

    def extract_identifier!(payload, headers, extractor, actor:, raw_body:)
      # A caller-supplied extractor is used INSTEAD of the built-in list, never
      # alongside it (FR-002b): a caller who knows the true field must never be
      # second-guessed by our inference.
      value = extractor ? extractor.call(payload, headers) : first_string(payload, ID_CANDIDATES)

      return value if value.is_a?(String) && !blank?(value)

      error = ValidationError.new(
        "no transaction identifier found in the notification " \
        "(tried #{ID_CANDIDATES.join(", ")}; supply extract_id: to override)",
        field: :transaction_id
      )
      reject!(error, ADVISORY_UNUSABLE, reason: :no_transaction_id, actor: actor, raw_body: raw_body)
    end

    # First candidate holding a non-blank String. A candidate present but holding a
    # Hash, Array, number, or blank string is skipped as though absent: coercing it
    # would only manufacture an identifier that fails one HTTP call later.
    def first_string(payload, candidates)
      candidates.each do |key|
        value = payload[key]
        return value if value.is_a?(String) && !blank?(value)
      end
      nil
    end

    # --- the retrieve ------------------------------------------------------

    # retries: false is load-bearing — see Transactions#retrieve and FR-009.
    def retrieve!(transaction_id, actor:, raw_body:, claimed:)
      client.transactions.retrieve(transaction_id, retries: false)
    rescue Error => e
      reject!(e, advisory_for(e),
              reason: reason_for(e),
              actor: actor,
              raw_body: raw_body,
              transaction_id: transaction_id,
              claimed: claimed)
    end

    def advisory_for(error)
      case error
      when NotFoundError then ADVISORY_UNUSABLE
      when AvailabilityError, RateLimitError, AuthenticationError then ADVISORY_TRANSIENT
      when ValidationError, ConflictError then ADVISORY_UNUSABLE
      else ADVISORY_UNEXPECTED
      end
    end

    def reason_for(error)
      case error
      when NotFoundError then :not_found
      when RateLimitError then :rate_limited
      when AvailabilityError then :unavailable
      when AuthenticationError then :credential_rejected
      else :rejected_by_bml
      end
    end

    # --- the comparison ---------------------------------------------------

    # Normalized for the COMPARISON ONLY (research R7). The two states observable
    # in the published document are uppercase, so a callback spelling one of them
    # differently would otherwise be read as a disagreement and pay the re-check
    # delay on every delivery for nothing. The reported status stays verbatim
    # (FR-005).
    def disagreement?(claimed, authoritative)
      return false if blank?(claimed) || !authoritative.is_a?(String)

      normalize_status(claimed) != normalize_status(authoritative)
    end

    def normalize_status(value)
      value.to_s.strip.upcase
    end

    # --- results, errors, auditing ----------------------------------------

    def build_result(transaction_id, record, claimed, rechecked)
      Models::StatusChangeResult.new(
        transaction_id: transaction_id,
        transaction: record,
        claimed_status: claimed,
        disagreed: disagreement?(claimed, record.state),
        rechecked: rechecked,
        advisory_http_status: ADVISORY_ACCEPTED
      )
    end

    def malformed!(message, actor:, raw_body:)
      reject!(
        ValidationError.new(message, field: :body),
        ADVISORY_MALFORMED, reason: :malformed_body, actor: actor, raw_body: raw_body
      )
    end

    # Tag the error with its advisory status, audit the outcome, then raise. Every
    # failure path in this class goes through here, which is how FR-015 ("every
    # notification handled, accepted or rejected, MUST emit an audit record") and
    # FR-016a ("every result and every error MUST carry an advisory status") are
    # kept true by construction rather than by remembering.
    def reject!(error, advisory, reason:, actor:, raw_body:, transaction_id: nil, claimed: nil)
      error.advisory_http_status = advisory
      audit(:rejected, actor: actor, raw_body: raw_body, reason: reason,
                       transaction_id: transaction_id, claimed: claimed, advisory: advisory)
      raise error
    end

    # One masked structured line through the client's existing logger — no separate
    # audit sink. Audit.emit_event scrubs the whole serialized record through
    # Masking.scrub, which is why the raw body is safe to include here (FR-004b)
    # even though it never appears on the result.
    #
    # NEITHER secret value is ever put in the record: that is enforced by not
    # writing them, since Masking.scrub detects card numbers, not secrets.
    def audit(outcome, actor:, raw_body:, result: nil, reason: nil,
              transaction_id: nil, claimed: nil, advisory: nil)
      subject = {
        transaction_id: result ? result.transaction_id : transaction_id,
        claimed_status: result ? result.claimed_status : claimed,
        disagreed: result ? result.disagreed? : nil,
        rechecked: result ? result.rechecked? : nil,
        advisory_http_status: result ? result.advisory_http_status : advisory,
        reason: reason,
        body: audit_safe_body(raw_body)
      }

      Audit.emit_event(
        client, action: :webhook_status_change, actor: actor, outcome: outcome, subject: subject
      )
    end

    # --- small shared helpers ---------------------------------------------

    # Inbound card-data screening (FR-011/FR-011a). Note what this does NOT do:
    # a PAN in the PAYLOAD does not reject the delivery. That deliberately diverges
    # from the library's treatment of caller-supplied input (Transactions,
    # Customers), where a PAN raises. The screen matches any Luhn-valid 13-19 digit
    # run, so on an inbound payload it can fire on a coincidental merchant
    # reference — and rejecting would advise a permanent status and discard a
    # genuine payment confirmation for good. Masking already satisfies FR-011 in
    # full, so refusal would buy nothing and cost availability. Do not "fix" this.
    #
    # An +actor+ IS caller-supplied, so it follows the outbound rule and raises.
    def screen_actor!(actor)
      return unless actor.is_a?(String)
      return unless Masking.looks_like_pan?(actor)

      error = ValidationError.new("actor must not contain card data", field: :actor)
      error.advisory_http_status = ADVISORY_UNEXPECTED
      raise error
    end

    # The raw body belongs in the audit record (FR-004b/FR-015), and an
    # invalid-UTF-8 body is exactly the kind that most needs recording — so the
    # bytes are made serializable before JSON.generate sees them rather than
    # letting a malformed delivery take down its own audit trail. Masking.scrub
    # then removes card-like data, as it does for every other field.
    def audit_safe_body(raw_body)
      raw_body.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, nested), out| out[key.to_sym] = deep_symbolize(nested) }
      when Array
        value.map { |nested| deep_symbolize(nested) }
      else
        value
      end
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
