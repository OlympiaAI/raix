# frozen_string_literal: true

module Raix
  module Runtime
    module Providers
      # OpenRouter Chat Completions adapter.
      class OpenRouter < Base
        DEFAULT_URL = "https://openrouter.ai/api/v1/chat/completions"

        def chat_completions(model:, messages:, params:, stream: nil)
          payload = { model:, messages: }.merge(filtered_params(params))

          if stream
            transport.post_stream(url: endpoint, headers: auth_headers, payload:, provider: "openrouter", &stream)
          else
            transport.post_json(url: endpoint, headers: auth_headers, payload:, provider: "openrouter")
          end
        end

        private

        def endpoint
          configuration.openrouter_base_url.presence || DEFAULT_URL
        end

        def auth_headers
          api_key = configuration.openrouter_api_key
          raise ConfigurationError, "Missing OpenRouter API key. Set `Raix.configure { |c| c.openrouter_api_key = ... }`." if api_key.blank?

          { "Authorization" => "Bearer #{api_key}" }
        end

        def filtered_params(params)
          params.except(:cache_at, :model).compact
        end
      end
    end
  end
end
