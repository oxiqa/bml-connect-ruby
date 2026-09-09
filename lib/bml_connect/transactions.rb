# frozen_string_literal: true

require "json"

require "deep_merge/rails_compat"

module BMLConnect
  # The transactions resource.
  #
  # This resource straddles two eras. The v1 methods — #create, #get, #list —
  # are RELEASED and depended on by six call sites in msgowl/website; they return
  # raw Faraday::Response objects and MUST NOT change behavior, signature, or
  # return type (FR-010). #create still posts to the undocumented-but-live
  # /public/transactions with the SHA1 signature, and is deprecated (FR-011).
  #
  # The v2 methods — #create_v2, #retrieve, #update, #capture, #cancel — are
  # additive. They speak the documented endpoints, return whitelisted
  # TransactionRecord value objects, raise the library's error hierarchy, and
  # emit audit records on state change (FR-019). They send no signature until UAT
  # observation settles whether v2 accepts one (FR-012).
  class Transactions < Resource
    END_POINT = "transactions"

    # Documented v2 create endpoint (FR-001).
    V2_CREATE_PATH = "/public/v2/transactions"
    # Shared retrieve/update/capture/cancel base (FR-006/007/008/009). The v1
    # retrieve path too, so a v1-created transaction is retrievable here.
    BASE_PATH = "/public/transactions"

    # Fields accepted on a v2 create body (variants 3 and 4 — direct amount, with
    # an existing customerId or an inline customer). Variants 1/2 (shop orders)
    # and 5 (foreign exchange) are out of scope and rejected by name (FR-020).
    CREATE_V2_FIELDS = %i[
      amount currency redirectUrl webhook localId customerReference
      customerId customer expires tokenizationDetails
    ].freeze

    # Presence of any of these signals an unsupported create variant.
    UNSUPPORTED_VARIANT_KEYS = %i[order fxQuoteId].freeze

    # Fields amendable via #update; only supplied keys are sent (FR-007).
    UPDATE_FIELDS = %i[customerReference localData pnr].freeze

    # Process-wide guard so the v1 deprecation warning fires at most once per
    # process (FR-011). Resettable so tests can assert the once-only behavior.
    class << self
      attr_accessor :v1_deprecation_warned
    end

    # Construction is inherited from Resource (which stores the client); no
    # override needed. @client is available to every method below.

    # --- v1, released surface (UNCHANGED behavior) --------------------------

    # Deprecated. Posts the signed body to the undocumented-but-live v1 endpoint
    # and returns a Faraday::Response, exactly as before. Emits a one-time
    # deprecation warning (FR-011) that does not alter behavior or return value.
    def create(params)
      warn_v1_deprecation
      transaction = BMLConnect::Models::Transaction.new(params)
      # generate signature
      transaction.sign(@client.api_key)
      @client.post(END_POINT, transaction.to_hash)
    end

    def get(id)
      @client.get(END_POINT + "/#{id}")
    end

    def list(params = {})
      @client.get(END_POINT, params)
    end

    # --- v2, additive value-object surface ----------------------------------

    # Create a transaction on the documented v2 endpoint. Validates locally
    # (amount is a positive Integer in minor units; currency present; customer
    # variant; tokenization rules; PAN screen) before any remote call. NEVER
    # auto-retried (FR-016): a timeout raises AvailabilityError after exactly one
    # attempt. Returns a TransactionRecord and emits a create audit record.
    def create_v2(details, actor: nil)
      attributes = symbolize(details)
      reject_unsupported_variants!(attributes)
      validate_amount!(attributes[:amount])
      require_present!(attributes, :currency)
      validate_customer_variant!(attributes)
      tokenization = build_tokenization(attributes)
      warn_tokenization_without_customer(attributes, tokenization)
      screen_for_pan!(attributes)
      screen_actor!(actor)

      body = build_create_body(attributes, tokenization)
      response = request(:post, V2_CREATE_PATH, body: body, retries: false)
      record = Models::TransactionRecord.new(response.body)
      audit(:create, actor: actor, subject: { transaction_id: record.id })
      record
    end

    # Retrieve a transaction by id. Value-object counterpart to #get, which
    # remains available. `state` is passed through verbatim (research R8). Not
    # audited (read). MAY retry (FR-016).
    def retrieve(id, actor: nil)
      require_id!(id)
      screen_actor!(actor)

      response = request(:get, "#{BASE_PATH}/#{id}")
      Models::TransactionRecord.new(response.body)
    end

    # Partially amend a transaction. Sends only the supplied keys among
    # customerReference/localData/pnr; never serializes an unset field as null.
    # Rejects an empty change set locally. Emits an update audit record (FR-017).
    def update(id, changes, actor: nil)
      require_id!(id)
      attributes = symbolize(changes)
      raise ValidationError.new("no changes supplied", field: :changes) if attributes.empty?

      screen_for_pan!(attributes)
      screen_actor!(actor)

      body = attributes.select { |key, _| UPDATE_FIELDS.include?(key) }
      raise ValidationError.new("no updatable fields supplied", field: :changes) if body.empty?

      response = request(:patch, "#{BASE_PATH}/#{id}", body: body)
      record = Models::TransactionRecord.new(response.body)
      audit(:update, actor: actor, subject: { transaction_id: id })
      record
    end

    # Capture a pre-authorized amount. `amount` obeys the same rule as create
    # (FR-008): a positive Integer in minor units. Money-moving, so NEVER
    # auto-retried (FR-016). Emits a capture audit record.
    def capture(id, amount:, actor: nil)
      require_id!(id)
      validate_amount!(amount)
      screen_actor!(actor)

      body = { id: id, amount: amount }
      response = request(:post, "#{BASE_PATH}/#{id}/capture", body: body, retries: false)
      record = Models::TransactionRecord.new(response.body)
      audit(:capture, actor: actor, subject: { transaction_id: id })
      record
    end

    # Cancel a transaction. Emits a cancel audit record. MAY retry (FR-016):
    # cancellation is not money-moving and is safe to re-send.
    def cancel(id, actor: nil)
      require_id!(id)
      screen_actor!(actor)

      response = request(:post, "#{BASE_PATH}/#{id}/cancel")
      record = Models::TransactionRecord.new(response.body)
      audit(:cancel, actor: actor, subject: { transaction_id: id })
      record
    end

    private

    # Diagnostic-only: send a minimal v2 create and return the RAW Faraday
    # response, for the UAT probe that resolves which field carries the hosted
    # payment URL ([UNVERIFIED] #1 / T021). Not part of the public surface.
    def raw_create_v2(details)
      attributes = symbolize(details)
      validate_amount!(attributes[:amount])
      require_present!(attributes, :currency)
      body = build_create_body(attributes, build_tokenization(attributes))
      request(:post, V2_CREATE_PATH, body: body, retries: false)
    end

    def build_create_body(attributes, tokenization)
      body = attributes.select { |key, _| CREATE_V2_FIELDS.include?(key) }
      body[:tokenizationDetails] = tokenization.to_h if tokenization
      body
    end

    # Validation object if tokenizationDetails supplied (validates on construct,
    # before any remote call); nil otherwise.
    def build_tokenization(attributes)
      return nil unless attributes.key?(:tokenizationDetails)

      Models::TokenizationDetails.new(attributes[:tokenizationDetails])
    end

    # Edge case: tokenization with no customer to attach the token to is
    # [UNVERIFIED] (#5). The library WARNS and forwards rather than blocking,
    # pending observation — it does not invent a rule BML has not stated.
    def warn_tokenization_without_customer(attributes, tokenization)
      return unless tokenization
      return unless blank?(attributes[:customerId]) && attributes[:customer].nil?

      logger = @client.respond_to?(:logger) ? @client.logger : nil
      logger&.warn(
        "[bml_connect] tokenizationDetails supplied without a customerId; " \
        "whether BML stores a token with no customer to attach it to is unverified"
      )
    end

    def reject_unsupported_variants!(attributes)
      UNSUPPORTED_VARIANT_KEYS.each do |key|
        next unless attributes.key?(key)

        raise ValidationError.new(
          "create variant using `#{key}` is not supported; use amount/currency (variant 3 or 4)",
          field: key
        )
      end
    end

    # FR-005/FR-008: a positive Integer in minor units. A Float, a String, zero,
    # a negative, or a boolean is rejected by name with no remote call. Never
    # coerced — guessing on a money field is unacceptable (research R5).
    def validate_amount!(amount)
      raise ValidationError.new("amount is required", field: :amount) if amount.nil?
      unless amount.is_a?(Integer)
        raise ValidationError.new("amount must be an Integer in minor units, not #{amount.class}", field: :amount)
      end
      return if amount.positive?

      raise ValidationError.new("amount must be a positive number of minor units", field: :amount)
    end

    def validate_customer_variant!(attributes)
      customer = attributes[:customer]
      if !blank?(attributes[:customerId]) && !customer.nil?
        raise ValidationError.new("customerId and inline customer are mutually exclusive", field: :customerId)
      end

      validate_inline_customer!(customer) unless customer.nil?
    end

    def validate_inline_customer!(customer)
      unless customer.respond_to?(:each_pair)
        raise ValidationError.new("customer must be an object with name and email", field: :customer)
      end

      inline = customer.transform_keys(&:to_sym)
      raise ValidationError.new("customer.name is required", field: :customer) if blank?(inline[:name])
      raise ValidationError.new("customer.email is required", field: :customer) if blank?(inline[:email])
    end

    def warn_v1_deprecation
      return if self.class.v1_deprecation_warned

      self.class.v1_deprecation_warned = true
      logger = @client.respond_to?(:logger) ? @client.logger : nil
      logger&.warn(
        "[bml_connect] transactions.create (legacy v1 POST /public/transactions) is deprecated; " \
        "migrate to transactions.create_v2 (POST /public/v2/transactions)"
      )
    end

    # --- shared local helpers (mirror the Customers resource) ---------------

    def symbolize(attributes)
      raise ValidationError, "expected a hash of attributes" unless attributes.respond_to?(:each_pair)

      attributes.transform_keys(&:to_sym)
    end

    def require_present!(attributes, field)
      return unless blank?(attributes[field])

      raise ValidationError.new("#{field} is required", field: field)
    end

    def require_id!(id)
      return unless blank?(id)

      raise ValidationError.new("transaction id is required", field: :id)
    end

    # Screen every caller-supplied string value for card data (FR-014): no field
    # is exempt. Recurses into nested hashes (inline customer, tokenization) and
    # arrays so a PAN cannot hide one level down.
    def screen_for_pan!(value, field: nil)
      case value
      when String then reject_pan_string!(value, field)
      when Hash   then value.each { |key, nested| screen_for_pan!(nested, field: field || key) }
      when Array  then value.each { |nested| screen_for_pan!(nested, field: field) }
      end
    end

    def reject_pan_string!(value, field)
      return unless Masking.looks_like_pan?(value)

      raise ValidationError.new("#{field} contains data that looks like a card number", field: field)
    end

    def screen_actor!(actor)
      return if actor.nil?
      return unless actor.is_a?(String)
      return unless Masking.looks_like_pan?(actor)

      raise ValidationError.new("actor must not contain card data", field: :actor)
    end

    def audit(action, actor:, subject:)
      Audit.emit_event(@client, action: action, actor: actor, outcome: :success, subject: subject)
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
