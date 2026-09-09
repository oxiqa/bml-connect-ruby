# frozen_string_literal: true

module BMLConnect
  # The customers resource: create, retrieve, list, partial-update, archive, and
  # charge a stored card under the /public-customers path family.
  #
  # Reached through a configured client as `client.customers`, mirroring the way
  # `client.transactions` is already exposed. Unlike transactions (which return
  # raw Faraday responses), this resource returns whitelisted value objects and
  # raises the library's error hierarchy on failure.
  #
  # `#charge` (feature 004) lives here because its endpoint is
  # `POST /public-customers/charge` — the customers path family this resource
  # already owns (FR-001, research R8). It is the only money-moving method on the
  # resource and is deliberately asymmetric with the others: it never
  # auto-retries and it audits failures as well as successes.
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

    # Charge a stored card against an already-created transaction — a
    # merchant-initiated payment with no cardholder present. Posts the three-key
    # body to `"#{PATH}/charge"` (POST /public-customers/charge). All three ids
    # are REQUIRED and validated locally; a missing or blank one is rejected by
    # name with NO remote call (FR-002). The charge carries no `amount` — the
    # named transaction supplies it (FR-003); to bill a different amount, create
    # a different transaction.
    #
    # NEVER auto-retried (FR-004): the charge schema carries no idempotency key,
    # so a retry could take payment twice. Exactly one attempt is made. A timeout
    # or transport failure raises AvailabilityError whose message names the
    # `transaction_id` (FR-005) — the only safe recovery is to retrieve the
    # transaction and reconcile, never to re-charge blindly.
    #
    # A returned TransactionRecord is a BUSINESS outcome (BML answered); a raised
    # error is a TRANSPORT or VALIDATION outcome. The two are never converted
    # into each other (FR-007). `state` is passed through verbatim. Every charge
    # — success or failure — emits an audit record (FR-010/FR-011); no card data
    # ever enters it (FR-008). The charge is applied in the environment the
    # client is configured for (FR-012), since it rides the same transport.
    #
    # `token_id` expects the stored card's `Token#id` — the value used as the
    # tokenId path parameter in `client.tokens.retrieve`. This is an inference
    # from consistent path-parameter naming, NOT yet confirmed against a live
    # environment (contracts/bml-remote.md [UNVERIFIED] #1 / task T001). This
    # method MUST NOT be relied on in production until it is confirmed (FR-013).
    def charge(customer_id:, transaction_id:, token_id:, actor: nil)
      subject = { customer_id: customer_id, transaction_id: transaction_id, token_id: token_id }

      validate_charge!(subject, actor)
      response = post_charge(subject, actor)

      record = Models::TransactionRecord.new(response.body)
      charge_audit(actor, subject.merge(state: record.state), :success)
      record
    end

    private

    # Local, pre-remote validation for a charge. A failure is audited (FR-011)
    # and re-raised with NO remote call made (FR-002, US1 scenario 2).
    def validate_charge!(subject, actor)
      require_charge_field!(subject[:customer_id], :customer_id)
      require_charge_field!(subject[:transaction_id], :transaction_id)
      require_charge_field!(subject[:token_id], :token_id)
      screen_for_pan!(subject)
      screen_actor!(actor)
    rescue ValidationError
      charge_audit(actor, subject, :validation_error)
      raise
    end

    # The single, never-retried remote attempt. Each failure mode is audited
    # before the error is re-raised so a raise never loses the trail (FR-011).
    def post_charge(subject, actor)
      body = {
        customerId: subject[:customer_id],
        transactionId: subject[:transaction_id],
        tokenId: subject[:token_id]
      }
      request(:post, "#{PATH}/charge", body: body, retries: false)
    rescue AvailabilityError => e
      charge_audit(actor, subject, :error)
      raise AvailabilityError, reconcile_message(e.message, subject[:transaction_id])
    rescue ValidationError
      # A non-2xx business rejection of the charge itself (400/422).
      charge_audit(actor, subject, :declined)
      raise
    rescue Error
      # Any other mapped failure (auth, not-found, rate limit): the charge did
      # not go through, but this is not a card decline.
      charge_audit(actor, subject, :error)
      raise
    end

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

    # Per-field presence check for the charge, so the error names exactly which
    # of the three required ids is missing (FR-002).
    def require_charge_field!(value, field)
      return unless blank?(value)

      raise ValidationError.new("#{field} is required", field: field)
    end

    # Charge auditing is deliberately separate from the shared #audit helper,
    # which hardcodes outcome: :success. A charge audits failures too (FR-011),
    # so the real outcome (:success, :declined, :validation_error, :error) is
    # passed through. Card data is scrubbed by Audit before the line is written.
    def charge_audit(actor, subject, outcome)
      Audit.emit_event(client, action: :charge, actor: actor, outcome: outcome, subject: subject)
    end

    # An AvailabilityError from a charge MUST name the transaction so the caller
    # can reconcile by retrieving it — the outcome is genuinely unknown (FR-005).
    def reconcile_message(original, transaction_id)
      "#{original} (charge outcome for transactionId #{transaction_id} is unknown; " \
        "retrieve the transaction to reconcile — do NOT re-charge blindly)"
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
