# frozen_string_literal: true

module BMLConnect
  class Webhooks
    # Sends a verified status change to the handler that owns it.
    #
    # A merchant registers ONE hook in BML's portal, so a single endpoint
    # receives notifications for every transaction the merchant creates —
    # enrolments, settlement charges, interactive payments, top-ups. BML's
    # payload is [UNVERIFIED] and in any case cannot say which of the
    # consumer's flows a transaction belongs to; only the consumer knows that.
    # So the resolver is supplied by the consumer and this class stays ignorant
    # of what the names mean.
    #
    #   router = BMLConnect::Webhooks::Router.new
    #   router.resolve { |result| Ownership.of(result.transaction_id) }
    #   router.on(:enrolment)  { |result| ... }
    #   router.on(:settlement) { |result| ... }
    #   router.otherwise       { |result| ... }
    #
    #   client.webhooks.handle(body: body, headers: headers, router: router)
    class Router
      class UnroutableError < BMLConnect::Error; end

      def initialize
        @handlers = {}
        @resolver = nil
        @fallback = nil
      end

      def resolve(&block)
        raise ArgumentError, "resolve requires a block" unless block

        @resolver = block
        self
      end

      # Registering twice is a mistake rather than an override: silently
      # replacing a handler hides the duplicate until a delivery goes to the
      # wrong place.
      def on(name, &block)
        raise ArgumentError, "a handler for #{name} is already registered" if @handlers.key?(key(name))
        raise ArgumentError, "on(#{name}) requires a block" unless block

        @handlers[key(name)] = block
        self
      end

      def otherwise(&block)
        raise ArgumentError, "otherwise requires a block" unless block

        @fallback = block
        self
      end

      def dispatch(result)
        raise UnroutableError, "no resolver registered" if @resolver.nil?

        name = @resolver.call(result)
        return handler_for!(name, result).call(result) unless name.nil?

        unless @fallback
          raise UnroutableError,
                "nothing owns transaction #{result.transaction_id} and no fallback is registered"
        end

        @fallback.call(result)
      end

      private

      def handler_for!(name, result)
        @handlers.fetch(key(name)) do
          raise UnroutableError,
                "resolver named #{name} for transaction #{result.transaction_id}, " \
                "but no handler is registered under it"
        end
      end

      def key(name)
        name.to_sym
      end
    end
  end
end
