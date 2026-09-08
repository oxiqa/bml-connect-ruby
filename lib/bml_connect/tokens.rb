# frozen_string_literal: true

module BMLConnect
  # Stored-card tokens: list, retrieve, and delete a customer's saved cards,
  # all nested under /public-customers/{customerId}/tokens.
  #
  # Read-and-delete ONLY, by contract. BML publishes no endpoint that creates a
  # token — a token is a side effect of a tokenizing transaction (feature 003),
  # completed by the cardholder on BML's hosted page. This resource therefore
  # exposes no create/tokenize/store/detokenize method, and its absence is
  # deliberate and test-enforced (FR-005/FR-008, SC-006). No operation here
  # accepts a card number, security code, or capture handle (FR-006).
  #
  # Reached through a configured client as `client.tokens`, mirroring
  # `client.customers`. Returns whitelisted value objects and raises the
  # library's error hierarchy on failure. Transient failures are retried by the
  # shared transport (research R9); only delete is audited (FR-014).
  class Tokens < Resource
    PATH = "/public-customers/%<customer_id>s/tokens"

    # List a customer's stored cards. Returns a Models::TokenList (Enumerable).
    # An empty collection is an empty list, never an error, and an auth failure
    # is never swallowed into one (FR-016, research R6). Not audited (read).
    def list(customer_id, actor: nil)
      require_customer_id!(customer_id)
      screen_actor!(actor)

      response = request(:get, collection_path(customer_id))
      Models::TokenList.new(response.body)
    end

    # Retrieve one stored card by id. Raises NotFoundError for an unknown token
    # or one belonging to another customer (tokens are scoped to their
    # customer). Not audited (read).
    def retrieve(customer_id, token_id, actor: nil)
      require_customer_id!(customer_id)
      require_token_id!(token_id)
      screen_actor!(actor)

      response = request(:get, member_path(customer_id, token_id))
      Models::Token.new(response.body)
    end

    # Delete (soft-delete) a stored card. Returns true on 204. Emits exactly one
    # audit record, written after the request settles — including after any
    # transient retries — so a retried delete is audited once, capturing the
    # final outcome (FR-013a x FR-014). The optional `actor` names who initiated
    # the deletion for the audit "who"; it must not carry cardholder data.
    def delete(customer_id, token_id, actor: nil)
      require_customer_id!(customer_id)
      require_token_id!(token_id)
      screen_actor!(actor)

      request(:delete, member_path(customer_id, token_id))
      audit(:delete, actor: actor, subject: { customer_id: customer_id, token_id: token_id })
      true
    end

    private

    def collection_path(customer_id)
      format(PATH, customer_id: customer_id)
    end

    def member_path(customer_id, token_id)
      "#{collection_path(customer_id)}/#{token_id}"
    end

    def require_customer_id!(customer_id)
      return unless blank?(customer_id)

      raise ValidationError.new("customer_id is required", field: :customer_id)
    end

    def require_token_id!(token_id)
      return unless blank?(token_id)

      raise ValidationError.new("token_id is required", field: :token_id)
    end

    # The actor reference is the only caller-supplied string this resource takes.
    # Screen it for card data so nothing PAN-like can reach an audit record.
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
