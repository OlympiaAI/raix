# frozen_string_literal: true

# Example Rails initializer for Raix standalone runtime.
# Place this in config/initializers/raix.rb

Raix.configure do |config|
  # Provider API keys
  config.openrouter_api_key = Rails.application.credentials.dig(:open_router, :api_key)
  config.openai_api_key = Rails.application.credentials.dig(:open_ai, :api_key)

  # Optional OpenAI headers
  # config.openai_organization_id = Rails.application.credentials.dig(:open_ai, :organization_id)
  # config.openai_project_id = Rails.application.credentials.dig(:open_ai, :project_id)

  # Runtime defaults
  config.model = "gpt-4o-mini"
  config.temperature = 0.2
  config.max_tokens = 1000
  config.max_tool_calls = 25

  # Transport behavior
  config.request_timeout = 120
  config.open_timeout = 30
  config.request_retries = 2
end

# Optional request logging/redaction hook
Raix.configure do |config|
  config.before_completion = lambda do |context|
    Rails.logger.info(
      event: "raix.chat_completion",
      model: context.current_model,
      message_count: context.messages.length
    )
    {}
  end
end
