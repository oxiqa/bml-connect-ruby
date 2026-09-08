# frozen_string_literal: true

module BMLConnect
  module Models
    # BML's list response: a { count, items } envelope, exposed as an
    # Enumerable over Customer value objects.
    #
    # BML types `count` as a string in the published contract. Whether it
    # arrives as "42" or 42 is unobserved (an [UNVERIFIED] marker), so the count
    # is coerced to an Integer and falls back to the actual item count if the
    # value is missing or non-numeric — it can never raise on a surprising type.
    class CustomerList
      include Enumerable

      attr_reader :count, :items

      def initialize(data = {})
        source = data || {}
        raw_items = source[:items] || source["items"] || []
        @items = raw_items.map { |item| Customer.new(item) }
        @count = coerce_count(source[:count] || source["count"])
      end

      def each(&block)
        items.each(&block)
      end

      def size
        items.size
      end

      def empty?
        items.empty?
      end

      private

      def coerce_count(raw)
        Integer(raw)
      rescue ArgumentError, TypeError
        items.size
      end
    end
  end
end
