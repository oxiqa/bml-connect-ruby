# frozen_string_literal: true

require 'faraday'
require 'faraday_middleware'
require 'deep_merge/rails_compat'
require 'logger'

module BMLConnect
  class Client
    BML_API_VERSION = '2.0'
    BML_APP_VERSION = 'bml-connect-ruby'
    BML_SIGN_METHOD = 'sha1'
    BML_SANDBOX_ENDPOINT = "https://api.uat.merchants.bankofmaldives.com.mv/public/"
    BML_PRODUCTION_ENDPOINT = "https://api.merchants.bankofmaldives.com.mv/public/"

    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_RETRY_BACKOFF = 0.5

    # Seconds to wait before the webhook handler's single re-check (feature 005,
    # FR-010b). Spent INSIDE the caller's request, so an endpoint whose own
    # response deadline is at or below this MUST set it to 0, which disables the
    # re-check entirely. A judgment, not an observed figure: see
    # specs/005-webhook-handler/contracts/bml-remote.md [UNVERIFIED] #4.
    DEFAULT_WEBHOOK_RECHECK_DELAY = 3

    attr_reader(:api_key, :app_id, :mode, :http_client, :transactions, :logger,
                :webhook_secret, :webhook_recheck_delay)
    attr_accessor(:timeout, :max_retries, :retry_backoff)

    def initialize(api_key: nil, app_id: nil, mode: nil, options: {})
      @api_key = api_key || (defined?(BML_API_KEY) ? BML_API_KEY : 'not-set')
      @app_id = app_id || (defined?(BML_APP_ID) ? BML_APP_ID : 'not-set')
      @mode = mode || (defined?(BML_MODE) ? BML_MODE : 'production')

      # Pull the customers-resource knobs out of options before the rest is
      # handed to Faraday, which would reject unknown keys.
      opts = options.dup
      @logger = pull_option(opts, :logger) { default_logger }
      @timeout = pull_option(opts, :timeout) { DEFAULT_TIMEOUT }
      @max_retries = pull_option(opts, :max_retries) { DEFAULT_MAX_RETRIES }
      @retry_backoff = pull_option(opts, :retry_backoff) { DEFAULT_RETRY_BACKOFF }

      # Webhook-handler knobs (feature 005). Pulled out for the same reason as the
      # four above: Faraday rejects keys it does not know. webhook_secret is
      # configuration supplied by the integrator (typically from the environment)
      # and MUST NEVER be hardcoded (FR-012).
      @webhook_secret = pull_option(opts, :webhook_secret) { nil }
      @webhook_recheck_delay = pull_option(opts, :webhook_recheck_delay) { DEFAULT_WEBHOOK_RECHECK_DELAY }

      @http_client = initialize_http_client(opts)
      @transactions = Transactions.new(self)
    end

    # Memoized customers resource, bound to this client's mode and credentials.
    def customers
      @customers ||= Customers.new(self)
    end

    # Memoized stored-card tokens resource, bound to this client's mode and
    # credentials. Read-and-delete only — see BMLConnect::Tokens.
    def tokens
      @tokens ||= Tokens.new(self)
    end

    # Memoized inbound notification handler, bound to this client's mode,
    # credentials, secret and re-check delay. See BMLConnect::Webhooks.
    def webhooks
      @webhooks ||= Webhooks.new(self)
    end

    def base_url
      @mode == 'production' ? BML_PRODUCTION_ENDPOINT : BML_SANDBOX_ENDPOINT
    end

    def set_http_client(client)
      @http_client = client
    end

    def post(action, params = {})
      data = params.merge({
        'apiVersion' => BML_API_VERSION,
        'appVersion' => BML_APP_VERSION,
        'signMethod' => BML_SIGN_METHOD,
      })
      @http_client.post(action, data.to_json)
    end

    def get(action, params = {})
      @http_client.get(action, params.slice(:page))
    end

    private

    # Take +key+ out of the options hash (so Faraday never sees it) and fall back
    # to the block when the caller did not supply it. An explicit nil is honored.
    def pull_option(opts, key)
      opts.key?(key) ? opts.delete(key) : yield
    end

    # Default audit/diagnostic logger. Emits masked structured lines to stdout;
    # integrators can inject their own via `options: { logger: ... }`.
    def default_logger
      logger = Logger.new($stdout)
      logger.progname = 'bml_connect'
      logger
    end

    def initialize_http_client(options)
      defaults = {
        url: base_url,
        headers: {
          'Content-Type' => 'application/json',
          'Accept' => 'application/json',
          'Authorization' =>  api_key,
        }
      };
      Faraday.new(defaults.deeper_merge!(options)) do |f|
        f.response :logger, nil, { headers: true, bodies: true } if defined?(DEBUG_ON)
        f.response :json, :parser_options => { :symbolize_names => true }
      end
    end
  end
end
