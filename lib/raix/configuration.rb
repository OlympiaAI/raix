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

    # DEPRECATED: Prefer openrouter_api_key
    attr_accessor_with_fallback :openrouter_client

    # DEPRECATED: Prefer openai_api_key
    attr_accessor_with_fallback :openai_client

    # Native API configuration for the standalone runtime.
    attr_accessor_with_fallback :openai_api_key
    attr_accessor_with_fallback :openrouter_api_key
    attr_accessor_with_fallback :openai_organization_id
    attr_accessor_with_fallback :openai_project_id
    attr_accessor_with_fallback :openai_base_url
    attr_accessor_with_fallback :openrouter_base_url
    attr_accessor_with_fallback :request_timeout
    attr_accessor_with_fallback :open_timeout
    attr_accessor_with_fallback :request_retries

    # The max_tool_calls option determines the maximum number of tool calls
    # before forcing a text response to prevent excessive function invocations.
    attr_accessor_with_fallback :max_tool_calls

    # A callable hook that runs before each chat completion request.
    # Receives a CompletionContext and can modify params and messages.
    # Use for: dynamic parameter resolution, logging, content filtering, PII redaction, etc.
    attr_accessor_with_fallback :before_completion

    DEFAULT_MAX_TOKENS = 1000
    DEFAULT_MAX_COMPLETION_TOKENS = 16_384
    DEFAULT_MODEL = "meta-llama/llama-3.3-8b-instruct:free"
    DEFAULT_TEMPERATURE = 0.0
    DEFAULT_MAX_TOOL_CALLS = 25
    DEFAULT_REQUEST_TIMEOUT = 120
    DEFAULT_OPEN_TIMEOUT = 30
    DEFAULT_REQUEST_RETRIES = 2

    # Initializes a new instance of the Configuration class with default values.
    def initialize(fallback: nil)
      self.temperature = DEFAULT_TEMPERATURE
      self.max_completion_tokens = DEFAULT_MAX_COMPLETION_TOKENS
      self.max_tokens = DEFAULT_MAX_TOKENS
      self.model = DEFAULT_MODEL
      self.max_tool_calls = DEFAULT_MAX_TOOL_CALLS
      self.request_timeout = DEFAULT_REQUEST_TIMEOUT
      self.open_timeout = DEFAULT_OPEN_TIMEOUT
      self.request_retries = DEFAULT_REQUEST_RETRIES
      self.fallback = fallback

      @legacy_client_warnings = {}
      @legacy_config_warning_emitted = false
      load_legacy_ruby_llm_config!
    end

    def client?
      # Support legacy client objects, standalone API keys, and RubyLLM migration shim.
      !!(openrouter_client || openai_client || openai_api_key || openrouter_api_key || ruby_llm_configured?)
    end

    def ruby_llm_configured?
      legacy_config = ruby_llm_config
      legacy_config&.openai_api_key || legacy_config&.openrouter_api_key ||
        legacy_config&.anthropic_api_key || legacy_config&.gemini_api_key
    end

    # Migration shim for RubyLLM-based configuration. Supported for one major cycle.
    def ruby_llm_config
      value = instance_variable_get("@ruby_llm_config")
      return value if value
      return unless fallback

      fallback.ruby_llm_config
    end

    def ruby_llm_config=(value)
      emit_legacy_config_warning_once!
      instance_variable_set("@ruby_llm_config", value)
      migrate_from_legacy_config(value)
    end

    def legacy_client_warning_emitted?(provider_key)
      @legacy_client_warnings[provider_key]
    end

    def mark_legacy_client_warning_emitted!(provider_key)
      @legacy_client_warnings[provider_key] = true
    end

    private

    attr_accessor :fallback

    def load_legacy_ruby_llm_config!
      return unless defined?(::RubyLLM)
      return unless ::RubyLLM.respond_to?(:config)

      self.ruby_llm_config = ::RubyLLM.config
    rescue StandardError
      nil
    end

    def migrate_from_legacy_config(legacy_config)
      return unless legacy_config

      self.openai_api_key ||= legacy_config.openai_api_key if legacy_config.respond_to?(:openai_api_key)
      self.openrouter_api_key ||= legacy_config.openrouter_api_key if legacy_config.respond_to?(:openrouter_api_key)
    end

    def emit_legacy_config_warning_once!
      return if @legacy_config_warning_emitted

      warn "DEPRECATION: RubyLLM config is deprecated in Raix. Configure API keys with `Raix.configure`."
      @legacy_config_warning_emitted = true
    end
  end
end
