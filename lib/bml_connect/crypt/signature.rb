# frozen_string_literal: true

module BMLConnect
  module Crypt
    module Signature

      attr_accessor :signature

      def sign(api_key)
        plain_signature  = 'amount=' + amount.to_s + '&currency=' + currency + '&apiKey=' + api_key
        @signature = Digest::SHA1.base64digest plain_signature
      end
    end
  end
end
