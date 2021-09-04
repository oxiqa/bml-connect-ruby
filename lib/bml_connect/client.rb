# frozen_string_literal: true

require 'faraday'
require 'deep_merge/rails_compat'

module BMLConnect
  class Client
    BML_API_KEY = 'not-set'
    BML_APP_ID = 'not-set'
    BML_API_VERSION = '2.0'
    BML_APP_VERSION = 'bml-connect-ruby'
    BML_SIGN_METHOD = 'sha1'
    BML_SANDBOX_ENDPOINT = "https://api.uat.merchants.bankofmaldives.com.mv/public/"
    BML_PRODUCTION_ENDPOINT = "https://api.merchants.bankofmaldives.com.mv/public/"

    def initialize(api_key: nil, app_id: nil, mode: "production", options: {})
      @api_key = api_key || BML_API_KEY
      @app_id = app_id || BML_APP_ID
      @mode = mode
      @http_client = initialize_http_client(options)
    end

    def base_url
      @mode == 'production' ? BML_PRODUCTION_ENDPOINT : BML_SANDBOX_ENDPOINT
    end

    def api_key
      @api_key
    end

    def http_client
      @http_client
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
      @http_client.post(action, data)
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
      Faraday.new(defaults.deeper_merge!(options))
    end
  end
end
