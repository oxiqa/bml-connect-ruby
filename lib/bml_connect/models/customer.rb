# frozen_string_literal: true

module BMLConnect
  module Models
    # A read-only value object for a BML customer.
    #
    # Attributes are whitelisted: only the fields below are pulled from a BML
    # response, so an unexpected key (e.g. a card field BML should never return
    # on a customer) cannot reach the object, a log line, or an audit record.
    class Customer
      ATTRIBUTES = %i[
        id name email companyId currency customerGroupId deleted
        billingEmail billingAddress1 billingAddress2 billingCity
        billingCountry billingPostCode invoicePrefix taxInformation taxId
        createdAt updatedAt
      ].freeze

      ATTRIBUTES.each { |attribute| attr_reader attribute }

      def initialize(data = {})
        source = data || {}
        ATTRIBUTES.each do |attribute|
          value = source.key?(attribute) ? source[attribute] : source[attribute.to_s]
          instance_variable_set("@#{attribute}", value)
        end
      end

      def deleted?
        deleted == true
      end

      def to_h
        ATTRIBUTES.each_with_object({}) do |attribute, hash|
          hash[attribute] = public_send(attribute)
        end
      end

      def ==(other)
        other.is_a?(Customer) && to_h == other.to_h
      end
      alias eql? ==

      def hash
        to_h.hash
      end

      def inspect
        present = to_h.reject { |_, value| value.nil? }
        "#<BMLConnect::Models::Customer #{present.inspect}>"
      end
    end
  end
end
