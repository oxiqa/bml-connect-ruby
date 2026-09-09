# frozen_string_literal: true

require "date"

module BMLConnect
  module Models
    # Input-only value object for the `tokenizationDetails` sub-object on a v2
    # create body. Never returned by BML; its presence is what instructs BML to
    # store the card (FR-003). Constructing one validates it locally — every
    # rule below runs before any remote call is made.
    #
    # The allowed `paymentType` and `recurringFrequency` values come from BML's
    # prose descriptions, not a JSON enum (the document declares none), so an
    # unrecognized value is rejected with a message quoting the documented set.
    class TokenizationDetails
      PAYMENT_TYPES = %w[RECURRING UNSCHEDULED].freeze
      RECURRING_FREQUENCIES = %w[
        DAILY WEEKLY BIWEEKLY FORTNIGHTLY MONTHLY QUARTERLY YEARLY AD_HOC
      ].freeze
      EXPIRY_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/.freeze

      # The documented keys, in serialization order. Readers are defined and
      # instance variables set by iterating this constant (as Token/Customer do),
      # so rubocop never sees the camelCase names as literals.
      FIELDS = %i[tokenize paymentType recurringFrequency expiryDate].freeze

      FIELDS.each { |field| attr_reader field }

      # +today+ is injectable so the future-date rule is testable without
      # stubbing the clock.
      def initialize(fields, today: nil)
        @today = today
        source = symbolize(fields)
        FIELDS.each { |field| instance_variable_set("@#{field}", source[field]) }
        validate!
      end

      # Serializes to exactly the documented keys, omitting any not supplied.
      def to_h
        FIELDS.each_with_object({}) { |field, hash| hash[field] = public_send(field) }
              .reject { |_, value| value.nil? }
      end

      private

      def validate!
        validate_tokenize!
        validate_payment_type!
        require_recurring_fields! if paymentType == "RECURRING"

        # FR-004: whenever expiryDate is supplied (RECURRING or not), it must be a
        # future date in yyyy-mm-dd form.
        validate_expiry! unless blank?(expiryDate)
      end

      def validate_tokenize!
        raise ValidationError.new("tokenize is required in tokenizationDetails", field: :tokenize) if tokenize.nil?
        return if [true, false].include?(tokenize)

        raise ValidationError.new("tokenize must be true or false", field: :tokenize)
      end

      def validate_payment_type!
        if blank?(paymentType)
          raise ValidationError.new("paymentType is required in tokenizationDetails", field: :paymentType)
        end
        return if PAYMENT_TYPES.include?(paymentType)

        raise ValidationError.new("paymentType must be one of #{PAYMENT_TYPES.join(", ")}", field: :paymentType)
      end

      def require_recurring_fields!
        if blank?(recurringFrequency)
          raise ValidationError.new("recurringFrequency is required when paymentType is RECURRING",
                                    field: :recurringFrequency)
        end
        unless RECURRING_FREQUENCIES.include?(recurringFrequency)
          raise ValidationError.new("recurringFrequency must be one of #{RECURRING_FREQUENCIES.join(", ")}",
                                    field: :recurringFrequency)
        end
        return unless blank?(expiryDate)

        raise ValidationError.new("expiryDate is required when paymentType is RECURRING", field: :expiryDate)
      end

      def validate_expiry!
        unless expiryDate.is_a?(String) && expiryDate =~ EXPIRY_FORMAT
          raise ValidationError.new("expiryDate must be in yyyy-mm-dd form", field: :expiryDate)
        end

        parsed =
          begin
            Date.iso8601(expiryDate)
          rescue ArgumentError
            raise ValidationError.new("expiryDate is not a valid date", field: :expiryDate)
          end

        reference = @today || Date.today
        raise ValidationError.new("expiryDate must be in the future", field: :expiryDate) unless parsed > reference
      end

      def symbolize(fields)
        unless fields.respond_to?(:each_pair)
          raise ValidationError.new("tokenizationDetails must be an object", field: :tokenizationDetails)
        end

        fields.transform_keys(&:to_sym)
      end

      def blank?(value)
        value.nil? || (value.is_a?(String) && value.strip.empty?)
      end
    end
  end
end
