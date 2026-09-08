# frozen_string_literal: true

require "json"
require "time"

module BMLConnect
  # Emits an audit record for every state-changing customer operation.
  #
  # Per the 2026-09-08 clarification (research R12), the record is written as a
  # single structured, masked log line through the client's existing logger.
  # There is no separate audit sink: auditing rides the same logging path the
  # rest of the library uses, and is observable in tests by inspecting the line.
  module Audit
    module_function

    # Build the who/what/when/outcome record and log it. Returns the record
    # (as a hash) so callers/tests can assert on it without parsing the line.
    def emit_event(client, action:, actor:, outcome:, subject:)
      record = {
        action: action,
        who: { app_id: client.app_id, actor: actor },
        subject: subject,
        outcome: outcome,
        at: Time.now.utc.iso8601
      }

      logger = client.respond_to?(:logger) ? client.logger : nil
      logger&.info(Masking.scrub(JSON.generate(record)))

      record
    end
  end
end
