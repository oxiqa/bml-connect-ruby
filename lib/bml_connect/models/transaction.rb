# frozen_string_literal: true

require 'set'

module BMLConnect
  module Models
    class Transaction

      include BMLConnect::Crypt::Signature

      REQUIRED_FIELDS = Set[:amount, :currency]

      attr_accessor :amount, :currency, :isPreauthorization, :provider, :redirectUrl, :localId, :customerReference
      
      def initialize(fields)
        # check for required fields
        raise ArgumentError.new("Missing Required Fields: [#{REQUIRED_FIELDS.join(', ')}]") unless REQUIRED_FIELDS.subset?(fields.keys.to_set)

        #initialize transaction props
        fields.each { |k,v| public_send("#{k}=", v) }
      end

      def to_hash()
        instance_variables.each_with_object({}) { |var, hash| hash[var.to_s.delete("@")] = instance_variable_get(var) }
      end
    end
  end
end
