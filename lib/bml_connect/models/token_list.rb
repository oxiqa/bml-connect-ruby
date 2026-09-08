# frozen_string_literal: true

module BMLConnect
  module Models
    # A customer's stored-card tokens, exposed as an Enumerable over Token
    # value objects.
    #
    # The list response shape is [UNVERIFIED] (research R4): the published
    # contract attaches the token array to the operation's `requestBody` rather
    # than to a response, so BML may send either a bare JSON array or a
    # `{ count, items }` envelope (the shape /public-customers uses). This parser
    # tolerates both and never raises on a surprising top-level type.
    class TokenList
      include Enumerable

      attr_reader :count, :items

      def initialize(data = {})
        raw_items = extract_items(data)
        @items = raw_items.map { |item| Token.new(item) }
        @count = coerce_count(count_hint(data))
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

      # The subset that has not been (soft-)deleted.
      def active
        items.reject(&:deleted?)
      end

      private

      def extract_items(data)
        return data if data.is_a?(Array)
        return [] unless data.is_a?(Hash)

        data[:items] || data["items"] || []
      end

      def count_hint(data)
        return data.size if data.is_a?(Array)
        return nil unless data.is_a?(Hash)

        data[:count] || data["count"]
      end

      def coerce_count(raw)
        Integer(raw)
      rescue ArgumentError, TypeError
        items.size
      end
    end
  end
end
