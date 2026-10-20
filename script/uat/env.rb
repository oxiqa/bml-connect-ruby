# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))

require 'bml_connect'

require 'json'
require 'logger'

begin
  require 'dotenv'
  Dotenv.load(File.expand_path('../../.env', __dir__))
rescue LoadError
  nil
end

module UATScript
  module_function

  def client
    require_env!('BML_API_KEY')
    BMLConnect::Client.new(
      api_key: ENV.fetch('BML_API_KEY'),
      app_id: ENV['BML_APP_ID'],
      mode: ENV.fetch('BML_ENV', 'sandbox'),
      options: { logger: Logger.new($stdout) }
    )
  end

  def require_env!(name)
    return unless ENV[name].to_s.strip.empty?

    abort "#{name} is not set in bml-connect-ruby/.env"
  end

  def heading(text)
    puts "\n== #{text}"
  end
end
