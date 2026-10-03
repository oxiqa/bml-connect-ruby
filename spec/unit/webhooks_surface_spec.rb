# frozen_string_literal: true

require "spec_helper"

# T024 [US2] — SC-004/SC-008i: two guarantees expressed as ABSENCES.
#
# A control that exists only as a default can be turned off by the next person
# in a hurry. These examples assert the switch does not exist to be found.
RSpec.describe BMLConnect::Webhooks, "public surface" do
  let(:client) { build_webhook_client }
  let(:webhooks) { client.webhooks }

  describe "no way to skip verification (FR-007, SC-004)" do
    it "rejects a verify: keyword outright" do
      expect { webhooks.handle(body: json_body, headers: json_headers, verify: false) }
        .to raise_error(ArgumentError, /unknown keyword/)
    end

    it "rejects every plausible spelling of an opt-out" do
      %i[verify skip_verify trust trust_payload unsafe verify_by_fetch].each do |option|
        expect { webhooks.handle(body: json_body, **{ option => false }) }
          .to raise_error(ArgumentError), "#{option} must not be accepted"
      end
    end

    it "accepts exactly the five documented keywords and no more" do
      keywords = BMLConnect::Webhooks.instance_method(:handle).parameters
                                     .select { |kind, _| %i[key keyreq].include?(kind) }
                                     .map(&:last)
      expect(keywords).to eq(%i[body headers presented_secret extract_id actor])
    end

    it "exposes exactly one public method" do
      expect(BMLConnect::Webhooks.public_instance_methods(false)).to eq(%i[handle])
    end
  end

  describe "no route to the untrusted payload (FR-004a, SC-008i)" do
    it "exposes no payload-shaped reader on the handler" do
      forbidden = %i[payload parse parsed_payload body raw_body last_payload]
      expect(BMLConnect::Webhooks.public_instance_methods(false) & forbidden).to be_empty
    end

    it "exposes no payload-shaped reader on the result" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      result = webhooks.handle(body: json_body, headers: json_headers)

      %i[payload body headers raw raw_body].each do |reader|
        expect(result).not_to respond_to(reader), "result.#{reader} must not exist"
      end
    end

    it "leaks no inbound field through to_h beyond the masked claimed_status" do
      stub_retrieve(client, "txn_1", transaction_body(state: "PAID"))
      body = json_body(transactionId: "txn_1", state: "PAID", secretish: "do-not-surface")

      result = webhooks.handle(body: body, headers: json_headers)

      expect(result.to_h.to_s).not_to include("do-not-surface")
    end
  end
end
