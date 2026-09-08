# frozen_string_literal: true

module BMLConnect
  module Models
    # A read-only value object for a BML stored-card token (BML's CustomerTokens
    # schema).
    #
    # Attributes are whitelisted: only the fields below are pulled from a BML
    # response, so an unexpected key — a full card number above all — cannot
    # reach the object, a log line, or an audit record (Constitution I,
    # FR-007/FR-009). The library mirrors BML's own field names verbatim and
    # invents no `last_four`/`scheme` alias (research R7).
    class Token
      ATTRIBUTES = %i[
        id brand provider token tokenType deleted tokenProvider
        tokenAgreementId tokenAgreementType tokenExpiryMonth tokenExpiryYear
        paddedCardNumber customerId companyId created updated
      ].freeze

      ATTRIBUTES.each { |attribute| attr_reader attribute }

      def initialize(data = {})
        source = data || {}
        ATTRIBUTES.each do |attribute|
          value = source.key?(attribute) ? source[attribute] : source[attribute.to_s]
          instance_variable_set("@#{attribute}", value)
        end
      end

      def deleted?
        deleted == true
      end

      # True for a token backed by a recurring/unscheduled agreement, which BML
      # signals by populating `tokenAgreementId`.
      def recurring?
        !blank?(tokenAgreementId)
      end

      def to_h
        ATTRIBUTES.each_with_object({}) do |attribute, hash|
          hash[attribute] = public_send(attribute)
        end
      end

      def ==(other)
        other.is_a?(Token) && to_h == other.to_h
      end
      alias eql? ==

      def hash
        to_h.hash
      end

      # Limited to the whitelist, so a token is always safe to log.
      def inspect
        present = to_h.reject { |_, value| value.nil? }
        "#<BMLConnect::Models::Token #{present.inspect}>"
      end

      private

      def blank?(value)
        value.nil? || (value.is_a?(String) && value.strip.empty?)
      end
    end
  end
end
