# frozen_string_literal: true

require 'json'

require 'deep_merge/rails_compat'

module BMLConnect
  class Transactions
    END_POINT = 'transactions'

    def initialize(client)
      @client = client
    end

    def create(params)
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
  end
end
