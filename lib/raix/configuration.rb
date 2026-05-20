# frozen_string_literal: true

module Raix
  # The Configuration class holds the configuration options for the Raix gem.
  class Configuration
    def self.attr_accessor_with_fallback(method_name)
      define_method(method_name) do
        value = instance_variable_get("@#{method_name}")
        return value if value
        return unless fallback

        fallback.public_send(method_name)
      end
      define_method("#{method_name}=") do |value|
        instance_variable_set("@#{method_name}", value)
      end
    end

    # The temperature option determines the randomness of the generated text.
    # Higher values result in more random output.
    attr_accessor_with_fallback :temperature

    # The max_tokens option determines the maximum number of tokens to generate.
    attr_accessor_with_fallback :max_tokens

    # The max_completion_tokens option determines the maximum number of tokens to generate.
    attr_accessor_with_fallback :max_completion_tokens

    # The model option determines the model to use for text generation. This option
    # is normally set in each class that includes the ChatCompletion module.
    attr_accessor_with_fallback :model

    # DEPRECATED: Use ruby_llm_config.openrouter_api_key instead
    attr_accessor_with_fallback :openrouter_client

    # DEPRECATED: Use ruby_llm_config.openai_api_key instead
    attr_accessor_with_fallback :openai_client

    # The max_tool_calls option determines the maximum number of tool calls
    # before forcing a text response to prevent excessive function invocations.
    attr_accessor_with_fallback :max_tool_calls

    # Access to RubyLLM configuration
    attr_accessor_with_fallback :ruby_llm_config

    # A callable hook that runs before each chat completion request.
    # Receives a CompletionContext and can modify params and messages.
    # Use for: dynamic parameter resolution, logging, content filtering, PII redaction, etc.
    attr_accessor_with_fallback :before_completion

    DEFAULT_MAX_TOKENS = 1000
    DEFAULT_MAX_COMPLETION_TOKENS = 16_384
    DEFAULT_MODEL = "meta-llama/llama-3.3-8b-instruct:free"
    DEFAULT_MAX_TOOL_CALLS = 25

    # Initializes a new instance of the Configuration class with default values.
    #
    # Note: temperature is intentionally not defaulted. Setting a non-nil
    # temperature here would force it into every request payload, and some
    # providers (e.g. Anthropic's Claude 4.7 family on OpenRouter) do not list
    # `temperature` in their supported parameters. Combined with
    # `provider.require_parameters: true` (which Raix sets when `json: true`),
    # an injected default of 0.0 causes OpenRouter to reject the request with
    # "No endpoints found that can handle the requested parameters." Callers
    # who want a specific temperature should set one explicitly.
    def initialize(fallback: nil)
      self.max_completion_tokens = DEFAULT_MAX_COMPLETION_TOKENS
      self.max_tokens = DEFAULT_MAX_TOKENS
      self.model = DEFAULT_MODEL
      self.max_tool_calls = DEFAULT_MAX_TOOL_CALLS
      self.ruby_llm_config = RubyLLM.config
      self.fallback = fallback
    end

    def client?
      # Support legacy openrouter_client/openai_client or new RubyLLM config
      !!(openrouter_client || openai_client || ruby_llm_configured?)
    end

    def ruby_llm_configured?
      ruby_llm_config&.openai_api_key || ruby_llm_config&.openrouter_api_key ||
        ruby_llm_config&.anthropic_api_key || ruby_llm_config&.gemini_api_key
    end

    private

    attr_accessor :fallback

    def get_with_fallback(method)
      value = instance_variable_get("@#{method}")
      return value if value
      return unless fallback

      fallback.public_send(method)
    end
  end
end
