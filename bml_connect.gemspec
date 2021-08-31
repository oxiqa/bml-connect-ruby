# frozen_string_literal: true

require_relative "lib/bml_connect/version"

Gem::Specification.new do |spec|
  spec.name          = "bml_connect"
  spec.version       = BMLConnect::VERSION
  spec.authors       = ["oxiqa"]
  spec.email         = ["dev@oxiqa.com"]

  spec.summary       = "Ruby gem for the Bank of Maldives Connect API"
  spec.description   = "Using this gem you can interact with your Bank of Maldives Connect API."
  spec.homepage      = "https://github.com/oxiqa/bml-connect-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.4.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/oxiqa/bml-connect-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/oxiqa/bml-connect-ruby/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_development_dependency "rspec", "~> 3.10.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
