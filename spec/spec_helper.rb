# frozen_string_literal: true

require "bml_connect"
require "webmock/rspec"

# Block all real network connections in the deterministic suites. The opt-in
# integration suite (spec/integration) re-enables real connections for itself
# and loads repo-local credentials from .env — see spec/integration/support.
WebMock.disable_net_connect!(allow_localhost: false)

# Load shared spec helpers (unit/contract). Integration support is loaded
# explicitly by the integration specs, which re-enable real connections.
Dir[File.join(__dir__, "support", "*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
