# frozen_string_literal: true

module BMLConnect
  # The customers resource: create, retrieve, list, partial-update and archive
  # BML customer records under the /public-customers path family.
  #
  # Reached through a configured client as `client.customers`, mirroring the way
  # `client.transactions` is already exposed. Unlike transactions (which return
  # raw Faraday responses), this resource returns whitelisted value objects and
  # raises the library's error hierarchy on failure.
  class Customers < Resource
    PATH = "/public-customers"

    # Fields BML accepts on create (per contracts/bml-remote.md). `currency` and
    # `paymentDue` are NOT here — they are update-only.
    CREATE_FIELDS = %i[
      name email billingEmail billingAddress1 billingAddress2 billingCity
      billingCountry billingPostCode customerGroup invoicePrefix
      taxInformation taxId
    ].freeze

    # Fields BML accepts on update. `customerGroup` is NOT here (create-only);
    # `currency` and `paymentDue` are (update-only).
    UPDATE_FIELDS = %i[
      name email billingEmail billingAddress1 billingAddress2 billingCity
      billingCountry billingPostCode currency paymentDue invoicePrefix
      taxInformation taxId
    ].freeze

    # Fields that get the lightweight email shape check (2026-09-08 clarification).
    EMAIL_FIELDS = %i[email billingEmail].freeze

    # Create a customer. Requires `name` and `email`; accepts any documented
    # optional field. Returns a Models::Customer carrying the BML-assigned id.
    def create(details, actor: nil)
      attributes = symbolize(details)
      require_present!(attributes, :name)
      require_present!(attributes, :email)
      validate_email_shape!(attributes)
      screen_for_pan!(attributes)
      screen_actor!(actor)

      body = attributes.select { |key, _| CREATE_FIELDS.include?(key) }
      response = request(:post, PATH, body: body)
      customer = Models::Customer.new(response.body)
      audit(:create, actor: actor, subject: { customer_id: customer.id })
      customer
    end

    # Retrieve a single customer by id. Not audited (read).
    def retrieve(customer_id, actor: nil)
      require_id!(customer_id)
      screen_actor!(actor)

      response = request(:get, "#{PATH}/#{customer_id}")
      Models::Customer.new(response.body)
    end

    # List customers under the company. No page parameters are sent — the
    # contract documents none (research R4). Not audited (read).
    def list(actor: nil)
      screen_actor!(actor)

      response = request(:get, PATH)
      Models::CustomerList.new(response.body)
    end

    # Partially update a customer. Sends only the keys supplied; never
    # serializes an unset field as null. Rejects an empty change set locally.
    def update(customer_id, changes, actor: nil)
      require_id!(customer_id)
      attributes = symbolize(changes)
      raise ValidationError.new("no changes supplied", field: :changes) if attributes.empty?

      validate_email_shape!(attributes)
      screen_for_pan!(attributes)
      screen_actor!(actor)

      body = attributes.select { |key, _| UPDATE_FIELDS.include?(key) }
      raise ValidationError.new("no updatable fields supplied", field: :changes) if body.empty?

      response = request(:patch, "#{PATH}/#{customer_id}", body: body)
      customer = Models::Customer.new(response.body)
      audit(:update, actor: actor, subject: { customer_id: customer_id })
      customer
    end

    # Archive (soft-delete) a customer. Named `archive`, not `delete`, because
    # BML retains the record with `deleted: true`. Returns true on 204.
    def archive(customer_id, actor: nil)
      require_id!(customer_id)
      screen_actor!(actor)

      request(:delete, "#{PATH}/#{customer_id}")
      audit(:archive, actor: actor, subject: { customer_id: customer_id })
      true
    end

    private

    def symbolize(attributes)
      raise ValidationError, "expected a hash of attributes" unless attributes.respond_to?(:each_pair)

      attributes.transform_keys(&:to_sym)
    end

    def require_present!(attributes, field)
      value = attributes[field]
      return unless blank?(value)

      raise ValidationError.new("#{field} is required", field: field)
    end

    def require_id!(customer_id)
      return unless blank?(customer_id)

      raise ValidationError.new("customer_id is required", field: :customer_id)
    end

    # Lightweight shape check only (2026-09-08 clarification / research R11):
    # the value must contain an @ and a domain part. Not strict RFC validation —
    # BML remains the authority on acceptance beyond this basic shape.
    def validate_email_shape!(attributes)
      EMAIL_FIELDS.each do |field|
        next unless attributes.key?(field)

        value = attributes[field]
        next if value.nil?
        next if valid_email_shape?(value)

        raise ValidationError.new("#{field} is not a valid email address", field: field)
      end
    end

    def valid_email_shape?(value)
      return false unless value.is_a?(String)

      !(value =~ /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/).nil?
    end

    # Screen every caller-supplied string value for card data (2026-09-08
    # clarification): no field is exempt.
    def screen_for_pan!(attributes)
      attributes.each do |field, value|
        next unless value.is_a?(String)
        next unless Masking.looks_like_pan?(value)

        raise ValidationError.new("#{field} contains data that looks like a card number", field: field)
      end
    end

    def screen_actor!(actor)
      return if actor.nil?
      return unless actor.is_a?(String)
      return unless Masking.looks_like_pan?(actor)

      raise ValidationError.new("actor must not contain card data", field: :actor)
    end

    def audit(action, actor:, subject:)
      Audit.emit_event(client, action: action, actor: actor, outcome: :success, subject: subject)
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
