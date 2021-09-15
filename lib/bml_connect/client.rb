# frozen_string_literal: true

require 'faraday'
require 'faraday_middleware'
require 'deep_merge/rails_compat'

module BMLConnect
  class Client
    BML_API_VERSION = '2.0'
    BML_APP_VERSION = 'bml-connect-ruby'
    BML_SIGN_METHOD = 'sha1'
    BML_SANDBOX_ENDPOINT = "https://api.uat.merchants.bankofmaldives.com.mv/public/"
    BML_PRODUCTION_ENDPOINT = "https://api.merchants.bankofmaldives.com.mv/public/"

    attr_reader(:api_key, :http_client, :transactions)

    def initialize(api_key: nil, app_id: nil, mode: nil, options: {})
      @api_key = api_key || (defined?(BML_API_KEY) ? BML_API_KEY : 'not-set')
      @app_id = app_id || (defined?(BML_APP_ID) ? BML_APP_ID : 'not-set')
      @mode = mode || (defined?(BML_MODE) ? BML_MODE : 'production')
      @mode = mode
      @http_client = initialize_http_client(options)
      @transactions = Transactions.new(self)
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
        f.response :logger, nil, { headers: true, bodies: true }
        f.response :json
      end
    end
  end
end
