# frozen_string_literal: true

require "dotenv"
require "faraday"
require "faraday/retry"
require "ruby_llm"
require "pry"
require "raix"

require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr" # the directory where your cassettes will be saved
  config.hook_into :webmock # or :fakeweb
  config.configure_rspec_metadata!
  config.ignore_localhost = true

  config.default_cassette_options = {
    match_requests_on: %i[method uri]
  }

  config.filter_sensitive_data("REDACTED") { |interaction| interaction.request.headers["Authorization"][0].sub("Bearer ", "") }
end

Dotenv.load

RubyLLM.configure do |config|
  config.openrouter_api_key = ENV.fetch("OR_ACCESS_TOKEN", nil)
  config.openai_api_key = ENV.fetch("OAI_ACCESS_TOKEN", nil)
  config.log_level = Logger::DEBUG
end

Raix.configure do |config|
  # Legacy support - can still set these if needed
  # config.openrouter_client = OpenRouter::Client.new(access_token: ENV.fetch("OR_ACCESS_TOKEN", nil))
  # config.openai_client = OpenAI::Client.new(access_token: ENV.fetch("OAI_ACCESS_TOKEN", nil))
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Specs tagged `:live` make real network calls to third-party services and
  # are excluded by default so CI doesn't hang on transient outages. Run them
  # locally with `LIVE_SPECS=1 bundle exec rspec`.
  config.filter_run_excluding(live: true) unless ENV["LIVE_SPECS"]

  config.before(:example, :novcr) do
    VCR.turn_off!
    WebMock.disable!
  end

  config.after(:example, :novcr) do
    VCR.turn_on!
    WebMock.enable!
  end
end
