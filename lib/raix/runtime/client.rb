# frozen_string_literal: true

module Raix
  module Runtime
    # Selects a provider and executes chat completion requests.
    class Client
      def initialize(configuration:)
        @configuration = configuration
      end

      def complete(model:, messages:, params:, stream:, openai_override:)
        provider_key = determine_provider(model, openai_override)
        legacy_response = complete_with_legacy_client(provider_key:, model:, messages:, params:, stream:)
        return legacy_response if legacy_response

        provider(provider_key).chat_completions(model:, messages:, params:, stream:)
      end

      private

      attr_reader :configuration

      def provider(key)
        @providers ||= {}
        @providers[key] ||= case key
                            when :openai
                              Providers::OpenAI.new(configuration:)
                            else
                              Providers::OpenRouter.new(configuration:)
                            end
      end

      def determine_provider(model, openai_override)
        return :openai if openai_override
        return :openai if model.to_s.match?(/^gpt-/) || model.to_s.match?(/^o\d/)

        :openrouter
      end

      def complete_with_legacy_client(provider_key:, model:, messages:, params:, stream:)
        client = provider_key == :openai ? configuration.openai_client : configuration.openrouter_client
        return nil unless client

        warn_deprecated_legacy_client(provider_key)

        return client.complete(model:, messages:, params:, stream:) if client.respond_to?(:complete)
        return client.chat(model:, messages:, params:, stream:) if client.respond_to?(:chat)

        nil
      end

      def warn_deprecated_legacy_client(provider_key)
        return if configuration.legacy_client_warning_emitted?(provider_key)

        warn "DEPRECATION: `#{provider_key}_client` is deprecated; configure `#{provider_key}_api_key` instead."
        configuration.mark_legacy_client_warning_emitted!(provider_key)
      end
    end
  end
end
