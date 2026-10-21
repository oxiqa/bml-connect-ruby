# frozen_string_literal: true

module BMLConnect
  module Models
    # What BMLConnect::Webhooks#handle returns: the authoritative outcome of one
    # inbound transaction-status notification (feature 005, FR-004).
    #
    # The important thing about this class is what it does NOT expose. There is no
    # +payload+, +body+, +headers+ or +raw+ reader, and there never should be
    # (FR-004a, SC-008i). A payload-shaped object here would invite
    # <tt>result.payload[:state]</tt> — a status read from an unauthenticated
    # source — which defeats the entire point of verify-by-fetch. The missing
    # accessor IS the control; a test asserts it stays missing.
    #
    # Payload-derived information is limited to individually named fields: the
    # masked +claimed_status+, the +disagreed?+ flag, and the masked
    # +event_type+. None of them is ever the reported status. The raw body
    # remains available for diagnosis where forensic detail belongs — in the
    # masked audit record (FR-004b).
    class StatusChangeResult
      # Whitelisted view, in a stable order.
      ATTRIBUTES = %i[
        transaction_id status changed_at claimed_status event_type
        disagreed rechecked advisory_http_status transaction
      ].freeze

      # The transaction identifier read from the payload (FR-002) — the one field
      # taken from the untrusted delivery and acted on.
      attr_reader :transaction_id

      # The authoritative record retrieved from BML (feature 003's model).
      attr_reader :transaction

      # What the payload claimed, masked. DIAGNOSTIC ONLY: never act on it.
      attr_reader :claimed_status

      # Which category of notification the payload says this is, masked — BML's
      # portal registers a hook per category ("Transaction change",
      # "Tokenisation status") and the delivery names one in +eventType+.
      #
      # ROUTING ONLY, and the distinction matters: a category selects WHICH
      # handler runs, never WHAT it believes. A forged category can therefore
      # only send a delivery to the wrong handler, where the authoritative
      # record still has to bear it out. A handler that acted on this field as
      # though it were a fact would reintroduce exactly the trust this class
      # exists to refuse.
      attr_reader :event_type

      # What the host application SHOULD return to BML. Advice, not control
      # (FR-016b).
      attr_reader :advisory_http_status

      def initialize(transaction_id:, transaction:, claimed_status: nil, event_type: nil,
                     disagreed: false, rechecked: false, advisory_http_status: 200)
        @transaction_id = transaction_id
        @transaction = transaction
        @claimed_status = claimed_status.nil? ? nil : Masking.scrub(claimed_status.to_s)
        @event_type = event_type.nil? ? nil : Masking.scrub(event_type.to_s)
        @disagreed = disagreed ? true : false
        @rechecked = rechecked ? true : false
        @advisory_http_status = advisory_http_status
      end

      # The authoritative status, verbatim (FR-005). Treat it as
      # current-as-of-retrieve, not as final.
      def status
        transaction&.state
      end

      # When the authoritative record last changed (FR-004).
      def changed_at
        transaction&.updated
      end

      # True when the payload's claim disagreed with the authoritative status.
      # The signature of a forgery attempt or a stale replay — worth recording,
      # never worth reporting as a status.
      def disagreed?
        @disagreed
      end

      # True when the single delayed re-check ran (FR-010).
      def rechecked?
        @rechecked
      end

      def to_h
        {
          transaction_id: transaction_id,
          status: status,
          changed_at: changed_at,
          claimed_status: claimed_status,
          event_type: event_type,
          disagreed: disagreed?,
          rechecked: rechecked?,
          advisory_http_status: advisory_http_status,
          transaction: transaction&.to_h
        }
      end

      def ==(other)
        other.is_a?(StatusChangeResult) && to_h == other.to_h
      end
      alias eql? ==

      def hash
        to_h.hash
      end

      # Limited to the whitelist, so a result is always safe to log — there is no
      # raw body on it to leak.
      def inspect
        summary = {
          transaction_id: transaction_id,
          status: status,
          claimed_status: claimed_status,
          event_type: event_type,
          disagreed: disagreed?,
          rechecked: rechecked?,
          advisory_http_status: advisory_http_status
        }
        "#<BMLConnect::Models::StatusChangeResult #{summary.inspect}>"
      end
    end
  end
end
