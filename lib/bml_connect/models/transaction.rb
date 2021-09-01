# frozen_string_literal: true

require 'set'

module BMLConnect
  module Models
    class Transaction

      REQUIRED_FIELDS = Set[:amount, :currency]

      attr_accessor :amount, :currency, :is_preauthorization, :provider, :redirect_url, :local_id, :customer_reference
      
      def initialize(fields)
        # check for required fields
        raise ArgumentError.new("Missing Required Fields: [#{REQUIRED_FIELDS.join(', ')}]") unless REQUIRED_FIELDS.subset?(fields.keys.to_set)

        #initialize transaction props
        fields.each { |k,v| public_send("#{k}=", v) }
      end
    end
  end
end
