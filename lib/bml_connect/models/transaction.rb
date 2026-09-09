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
        # `REQUIRED_FIELDS.to_a.join` — NOT `REQUIRED_FIELDS.join`: Set#join was
        # added in Ruby 3.0 but the gemspec floor is 2.3, so on Ruby 2.7 (which
        # msgowl/website runs) a bare Set#join raised NoMethodError instead of the
        # intended ArgumentError. Bug fix, not a behavior change — it makes this
        # path do what spec/transaction_spec.rb already asserts (research R11).
        raise ArgumentError.new("Missing Required Fields: [#{REQUIRED_FIELDS.to_a.join(', ')}]") unless REQUIRED_FIELDS.subset?(fields.keys.to_set)

        #initialize transaction props
        fields.each { |k,v| public_send("#{k}=", v) }
      end

      def to_hash()
        instance_variables.each_with_object({}) { |var, hash| hash[var.to_s.delete("@")] = instance_variable_get(var) }
      end
    end
  end
end
