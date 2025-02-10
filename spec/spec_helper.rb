# frozen_string_literal: true

require "dotenv"
require "faraday"
require "faraday/retry"
require "open_router"
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

retry_options = {
  max: 2,
  interval: 0.05,
  interval_randomness: 0.5,
  backoff_factor: 2
}

OpenRouter.configure do |config|
  config.faraday do |f|
    f.request :retry, retry_options
    f.response :logger, ::Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
      logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
    end
  end
end

Raix.configure do |config|
  config.openrouter_client = OpenRouter::Client.new(access_token: ENV["OR_ACCESS_TOKEN"])
  config.openai_client = OpenAI::Client.new(access_token: ENV["OAI_ACCESS_TOKEN"]) do |f|
    f.request :retry, retry_options
    f.response :logger, ::Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
      logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
    end
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:example, :novcr) do
    VCR.turn_off!
    WebMock.disable!
  end

  config.after(:example, :novcr) do
    VCR.turn_on!
    WebMock.enable!
  end
end
