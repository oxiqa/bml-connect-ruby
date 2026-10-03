# frozen_string_literal: true

require "spec_helper"

# T004 — the advisory-status carrier and the one new error class.
#
# FR-016a requires EVERY result and error this feature produces to carry an
# advisory HTTP status. Rather than a parallel hierarchy of status-specific
# classes (which would break callers matching on AvailabilityError), the value
# rides on the existing base error as an accessor the webhook path tags.
RSpec.describe "webhook error carriers" do
  describe BMLConnect::Error do
    it "carries an advisory_http_status that defaults to nil" do
      expect(BMLConnect::Error.new("x").advisory_http_status).to be_nil
    end

    it "is writable and readable on every existing error class" do
      [
        BMLConnect::ValidationError, BMLConnect::AuthenticationError,
        BMLConnect::NotFoundError, BMLConnect::ConflictError,
        BMLConnect::RateLimitError, BMLConnect::AvailabilityError,
        BMLConnect::UnverifiedFieldError, BMLConnect::WebhookRejectedError
      ].each do |klass|
        error = klass.new("boom")
        error.advisory_http_status = 503
        expect(error.advisory_http_status).to eq(503), "#{klass} lost the advisory status"
      end
    end

    it "does not disturb ValidationError's field" do
      error = BMLConnect::ValidationError.new("bad", field: :body)
      error.advisory_http_status = 400
      expect(error.field).to eq(:body)
    end
  end

  describe BMLConnect::WebhookRejectedError do
    it "descends from the library base error" do
      expect(BMLConnect::WebhookRejectedError.ancestors).to include(BMLConnect::Error)
    end

    # FR-016/SC-008: a failed secret check must be observably distinguishable
    # from a malformed body. Both would otherwise be ValidationError, separable
    # only by a `field:` value — too weak for something operators alert on.
    it "is a distinct class from ValidationError" do
      expect(BMLConnect::WebhookRejectedError.new("x")).not_to be_a(BMLConnect::ValidationError)
    end
  end
end
