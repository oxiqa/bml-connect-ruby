# frozen_string_literal: true

require "bml_connect"

# Load UAT credentials from THIS repository's .env only. The explicit path keeps
# the integration suite from picking up a .env elsewhere on the machine — the
# credentials are scoped to this repo (see .env.example, .gitignore).
begin
  require "dotenv"
  Dotenv.load(File.expand_path("../../.env", __dir__))
rescue LoadError
  # dotenv is a development dependency; if it is unavailable the suite still
  # runs against real environment variables (and skips when none are set).
end

# Helpers for the opt-in, credential-gated UAT suite.
module UATSupport
  module_function

  # The raw UAT key from the repo-local .env. Accepts either BML_API_KEY or the
  # MPG_API_KEY name already used in this repo's .env.
  def api_key
    ENV["BML_API_KEY"] || ENV["MPG_API_KEY"]
  end

  # True only when a non-empty UAT key is present.
  def credentials?
    key = api_key
    !key.nil? && !key.strip.empty?
  end

  # The UAT suite hits BML for real and creates live customer records, so it
  # runs only when explicitly opted in (BML_RUN_UAT=1) AND credentials exist.
  # A plain `bundle exec rspec` never fires live calls by accident.
  def enabled?
    credentials? && %w[1 true yes].include?(ENV.fetch("BML_RUN_UAT", "").strip.downcase)
  end

  def client
    BMLConnect::Client.new(
      api_key: api_key,
      # app_id is optional here: BML authenticates on the key alone, and the key
      # (a JWT) already encodes the appId. Supplied only when set, for the audit
      # "who" default.
      app_id: ENV["BML_APP_ID"] || ENV["MPG_APP_ID"],
      mode: ENV.fetch("BML_ENV", "sandbox")
    )
  end
end

RSpec.configure do |config|
  # Integration examples talk to the real BML UAT host. Skip cleanly when no
  # key is configured, and open up the network only for the tagged example.
  config.before(:each, :integration) do
    skip "UAT suite off — set BML_RUN_UAT=1 with a key in .env to run live" unless UATSupport.enabled?
    WebMock.allow_net_connect!
  end

  config.after(:each, :integration) do
    WebMock.disable_net_connect!(allow_localhost: false)
  end
end
