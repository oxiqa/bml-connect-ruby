# frozen_string_literal: true

require "spec_helper"

# T002 — the retry fix that makes FR-009's two-retrieve cap real.
#
# `Transactions#retrieve` was released (feature 003) with the shared bounded
# retry ON. That is correct for a caller reconciling by hand, and wrong for the
# webhook path: FR-009 caps a notification at two retrieves counted in HTTP
# calls, so one delivery arriving while BML is flaky would otherwise make up to
# six requests (3 per retrieve x 2) — and a forger could use a flaky BML to
# triple their amplification (research R3).
RSpec.describe BMLConnect::Transactions, "#retrieve retry policy" do
  let(:client) { build_client }
  let(:transactions) { client.transactions }
  let(:url) { txn_url(client, "txn_1") }

  describe "default (feature 003's released behavior, unchanged)" do
    it "retries a timeout up to the client's bounded max" do
      stub_request(:get, url).to_timeout

      expect { transactions.retrieve("txn_1") }.to raise_error(BMLConnect::AvailabilityError)
      expect(a_request(:get, url)).to have_been_made.times(client.max_retries + 1)
    end

    it "returns the record without retrying when the first attempt succeeds" do
      stub_request(:get, url).to_return(json_response(transaction_body, 200))

      expect(transactions.retrieve("txn_1").id).to eq("txn_1")
      expect(a_request(:get, url)).to have_been_made.once
    end
  end

  describe "retries: false (what the webhook handler passes)" do
    it "makes exactly one attempt on a timeout and raises immediately" do
      stub_request(:get, url).to_timeout

      expect { transactions.retrieve("txn_1", retries: false) }
        .to raise_error(BMLConnect::AvailabilityError)
      expect(a_request(:get, url)).to have_been_made.once
    end

    it "makes exactly one attempt on a 503 rather than burning the retry budget" do
      stub_request(:get, url).to_return(json_response({ message: "upstream" }, 503))

      expect { transactions.retrieve("txn_1", retries: false) }
        .to raise_error(BMLConnect::AvailabilityError)
      expect(a_request(:get, url)).to have_been_made.once
    end

    it "still returns a record on success" do
      stub_request(:get, url).to_return(json_response(transaction_body(state: "PAID"), 200))

      expect(transactions.retrieve("txn_1", retries: false).state).to eq("PAID")
    end
  end
end
