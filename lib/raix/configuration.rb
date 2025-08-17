# frozen_string_literal: true

require_relative "providers/open_router_provider"
require_relative "providers/openai_provider"

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

    attr_writer :openrouter_client, :openai_client

    # The openrouter_client option determines the default client to use for communication.
    def openrouter_client
      value = @openrouter_client
      return value if value
      return unless fallback

      fallback.openrouter_client
    end

    # The openai_client option determines the OpenAI client to use for communication.
    def openai_client
      value = @openai_client
      return value if value
      return unless fallback

      fallback.openai_client
    end

    # The max_tool_calls option determines the maximum number of tool calls
    # before forcing a text response to prevent excessive function invocations.
    attr_accessor_with_fallback :max_tool_calls

    DEFAULT_MAX_TOKENS = 1000
    DEFAULT_MAX_COMPLETION_TOKENS = 16_384
    DEFAULT_MODEL = "meta-llama/llama-3.3-8b-instruct:free"
    DEFAULT_TEMPERATURE = 0.0
    DEFAULT_MAX_TOOL_CALLS = 25

    # Initializes a new instance of the Configuration class with default values.
    def initialize(fallback: nil)
      self.temperature = DEFAULT_TEMPERATURE
      self.max_completion_tokens = DEFAULT_MAX_COMPLETION_TOKENS
      self.max_tokens = DEFAULT_MAX_TOKENS
      self.model = DEFAULT_MODEL
      self.max_tool_calls = DEFAULT_MAX_TOOL_CALLS
      self.fallback = fallback
      @providers = {}
    end

    def client?
      !!(openrouter_client || openai_client || @providers.any?)
    end

    def register_provider(name, client)
      @providers[name] = client
    end

    # Find the provider to use based on the name, if given.
    # Fall back to the next registered provider if no name is provided.
    # We must use the openai_client and openrouter_client methods so that the
    # previous fallback behavior is preserved.
    def provider(name = nil)
      # Prioritize use of registered providers before using openai_client or openrouter_client.
      return @providers[name] if name && @providers.key?(name)

      # if openai is specified explicitly, use openai_client.
      # if openrouter_client is set, use it for backwards compatibility.
      # finally, use the named or first registered provider.
      if name == :openai
        openai_client ? Providers::OpenAIProvider.new(openai_client) : nil
      elsif name == :openrouter || openrouter_client
        openrouter_client ? Providers::OpenRouterProvider.new(openrouter_client) : nil
      elsif @providers.any?
        @providers.values.first
      elsif fallback
        fallback.provider(name)
      end
    end

    attr_reader :providers

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
