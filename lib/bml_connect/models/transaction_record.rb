# frozen_string_literal: true

module BMLConnect
  module Models
    # A read-only value object for a BML transaction (the v2 create/retrieve
    # response). Named +TransactionRecord+, not +Transaction+, because the latter
    # is already the v1 *request* builder that `transactions.create` depends on
    # (research R9); renaming it would break a released method.
    #
    # Attributes are whitelisted: only the fields below are pulled from a BML
    # response, so an unexpected key — a card number above all — cannot reach the
    # object, a log line, or an audit record (Constitution I, FR-014).
    class TransactionRecord
      ATTRIBUTES = %i[
        id created updated amount currency payCurrency merchantId
        provider providerHistory state accountingState qr securityWord
        canRefundIfConfirmed externalImport externalId localId paymentToken
        history appVersion apiVersion redirectUrl costStructure
        providerDisplayName paddedCardNumber customerId
        customerReference localData pnr tokenizationDetails
      ].freeze

      # Fields that may carry the hosted payment link, in resolution order. `url`
      # is the v1 field, absent from the v2 schema ([UNVERIFIED] #1); `redirectUrl`
      # and `qr.url` are the documented v2 fields. `url` is deliberately NOT in
      # ATTRIBUTES: the hosted payment page is a completion secret (FR-015), so it
      # is never whitelisted, never in #to_h, and never in #inspect. It is
      # reachable only through the explicit #payment_url accessor.
      PAYMENT_URL_KEYS = %i[url redirectUrl].freeze

      # Not whitelisted, for the same reason `url` is not: it completes a
      # payment. Reachable only through #next_action.
      CHALLENGE_KEY = :nextAction

      # Fields in which BML reports what it DID about tokenization, as opposed
      # to +tokenizationDetails+, which is the request WE sent and which BML
      # echoes back — an echo says only that we asked. `tokenize` and
      # `tokenizationMethod` are the documented Transaction fields; the rest
      # were observed on live UAT notifications (2026-10-21) and appear in no
      # published schema.
      #
      # Whitelisted separately and reachable only through #tokenization_report:
      # they exist to be logged while diagnosing a card that was not stored, so
      # they do not belong in #to_h or #inspect, and keeping them a whitelist
      # preserves the rule that no unexpected key can reach a log line.
      TOKENIZATION_FIELDS = %i[
        tokenize tokenizationMethod tokenisationStatus tokenizationStatus
        token clientSideTokenId initiator
      ].freeze

      ATTRIBUTES.each { |attribute| attr_reader attribute }

      def initialize(data = {})
        @source = normalize(data || {})
        ATTRIBUTES.each do |attribute|
          instance_variable_set("@#{attribute}", @source[attribute])
        end
      end

      # The hosted payment URL to send the cardholder to. Reads the first present
      # of `url`, `redirectUrl`, `qr.url`. RAISES rather than returning nil when
      # none is present: a nil here would surface as a blank redirect in checkout,
      # a silent failure in a money path (research R7). Resolving which field is
      # authoritative on v2 is [UNVERIFIED] #1 (T021).
      def payment_url
        candidate = PAYMENT_URL_KEYS.map { |key| @source[key] }.find { |value| !blank?(value) }
        candidate = qr_url if blank?(candidate)

        if blank?(candidate)
          raise UnverifiedFieldError,
                "no hosted payment URL present in the transaction response " \
                "(see contracts/bml-remote.md [UNVERIFIED] #1)"
        end

        candidate
      end

      # BML's Transaction schema: "Returns a URL when 3DS authentication is
      # required; this URL must be opened to complete the 3DS challenge."
      def next_action
        presence(@source[CHALLENGE_KEY])
      end

      # Whether the gateway kept the card. It echoes `tokenizationDetails` back
      # with the outcome, which is the only field that says so.
      #
      # NOT `paymentToken`: that is the acquirer's authorisation code — the
      # trailing six digits of `externalId` — and is present on any authorised
      # payment, tokenized or not (observed in UAT 2026-10-21).
      def tokenized?
        tokenization_detail("tokenize") == true
      end

      # The token this transaction created, as listed under the customer.
      # `tokenId` and `tokenObjectId` carry the same value; both are read so a
      # response that drops one still resolves.
      def stored_token_id
        return nil unless tokenized?

        id = tokenization_detail("tokenId")
        blank?(id) ? presence(tokenization_detail("tokenObjectId")) : id
      end

      # What the gateway said about tokenization, for a log line. Present keys
      # only: an empty hash means BML reported nothing at all about the card,
      # which is itself the answer when a tokenizing transaction stored none.
      #
      # Every string is scrubbed, because these fields are undocumented and a
      # diagnostic must not be the one place a card number reaches a log.
      def tokenization_report
        report = TOKENIZATION_FIELDS.each_with_object({}) do |key, hash|
          value = @source[key]
          hash[key] = value.is_a?(String) ? Masking.scrub(value) : value unless blank?(value)
        end
        report[:tokenizationDetails] = scrub_details if tokenizationDetails.respond_to?(:each_pair)
        report
      end

      # Whitelisted view. The hosted payment `url` is never included (FR-015).
      def to_h
        ATTRIBUTES.each_with_object({}) do |attribute, hash|
          hash[attribute] = public_send(attribute)
        end
      end

      def ==(other)
        other.is_a?(TransactionRecord) && to_h == other.to_h
      end
      alias eql? ==

      def hash
        to_h.hash
      end

      # Limited to the whitelist, so a record is always safe to log — the hosted
      # payment `url` never appears here.
      def inspect
        present = to_h.reject { |_, value| value.nil? }
        "#<BMLConnect::Models::TransactionRecord #{present.inspect}>"
      end

      private

      def tokenization_detail(key)
        details = tokenizationDetails
        return nil unless details.respond_to?(:[])

        details[key].nil? ? details[key.to_sym] : details[key]
      end

      def scrub_details
        tokenizationDetails.each_with_object({}) do |(key, value), hash|
          hash[key.to_sym] = value.is_a?(String) ? Masking.scrub(value) : value
        end
      end

      def presence(value)
        blank?(value) ? nil : value
      end

      def qr_url
        return nil unless qr.is_a?(Hash)

        qr[:url] || qr["url"]
      end

      # Symbol-first access with a string fallback, over every key we might read
      # (whitelist, plus the payment-URL candidates and the tokenization
      # diagnostics).
      def normalize(source)
        keys = ATTRIBUTES + PAYMENT_URL_KEYS + TOKENIZATION_FIELDS + [CHALLENGE_KEY]
        keys.each_with_object({}) do |key, hash|
          hash[key] = source.key?(key) ? source[key] : source[key.to_s]
        end
      end

      def blank?(value)
        value.nil? || (value.is_a?(String) && value.strip.empty?)
      end
    end
  end
end
