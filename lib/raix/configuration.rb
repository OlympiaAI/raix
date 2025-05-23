# frozen_string_literal: true

module Raix
  # The Configuration class holds the configuration options for the Raix gem.
  class Configuration
    # The temperature option determines the randomness of the generated text.
    # Higher values result in more random output.
    def temperature
      get_with_fallback(:temperature)
    end
    attr_writer :temperature, :max_tokens, :max_completion_tokens, :model, :openrouter_client, :openai_client

    # The max_tokens option determines the maximum number of tokens to generate.
    def max_tokens
      get_with_fallback(:max_tokens)
    end

    # The max_completion_tokens option determines the maximum number of tokens to generate.
    def max_completion_tokens
      get_with_fallback(:max_completion_tokens)
    end

    # The model option determines the model to use for text generation. This option
    # is normally set in each class that includes the ChatCompletion module.
    def model
      get_with_fallback(:model)
    end

    # The openrouter_client option determines the default client to use for communication.
    def openrouter_client
      get_with_fallback(:openrouter_client)
    end

    # The openai_client option determines the OpenAI client to use for communication.
    def openai_client
      get_with_fallback(:openai_client)
    end

    DEFAULT_MAX_TOKENS = 1000
    DEFAULT_MAX_COMPLETION_TOKENS = 16_384
    DEFAULT_MODEL = "meta-llama/llama-3-8b-instruct:free"
    DEFAULT_TEMPERATURE = 0.0

    # Initializes a new instance of the Configuration class with default values.
    def initialize(fallback: nil)
      self.temperature = DEFAULT_TEMPERATURE
      self.max_completion_tokens = DEFAULT_MAX_COMPLETION_TOKENS
      self.max_tokens = DEFAULT_MAX_TOKENS
      self.model = DEFAULT_MODEL
      self.fallback = fallback
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
