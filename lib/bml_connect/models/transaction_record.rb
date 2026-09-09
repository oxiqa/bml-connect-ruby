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
        customerReference localData pnr
      ].freeze

      # Fields that may carry the hosted payment link, in resolution order. `url`
      # is the v1 field, absent from the v2 schema ([UNVERIFIED] #1); `redirectUrl`
      # and `qr.url` are the documented v2 fields. `url` is deliberately NOT in
      # ATTRIBUTES: the hosted payment page is a completion secret (FR-015), so it
      # is never whitelisted, never in #to_h, and never in #inspect. It is
      # reachable only through the explicit #payment_url accessor.
      PAYMENT_URL_KEYS = %i[url redirectUrl].freeze

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

      # True once BML has stored a card for this transaction. The token itself is
      # read via the tokens resource (feature 002); this only signals presence.
      def tokenized?
        !blank?(paymentToken)
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

      def qr_url
        return nil unless qr.is_a?(Hash)

        qr[:url] || qr["url"]
      end

      # Symbol-first access with a string fallback, over every key we might read
      # (whitelist plus the payment-URL candidates).
      def normalize(source)
        (ATTRIBUTES + PAYMENT_URL_KEYS).each_with_object({}) do |key, hash|
          hash[key] = source.key?(key) ? source[key] : source[key.to_s]
        end
      end

      def blank?(value)
        value.nil? || (value.is_a?(String) && value.strip.empty?)
      end
    end
  end
end
