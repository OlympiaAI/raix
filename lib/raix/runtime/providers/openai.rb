# frozen_string_literal: true

module Raix
  module Runtime
    module Providers
      # OpenAI Chat Completions adapter.
      class OpenAI < Base
        DEFAULT_URL = "https://api.openai.com/v1/chat/completions"

        def chat_completions(model:, messages:, params:, stream: nil)
          payload = { model:, messages: }.merge(filtered_params(params))

          if stream
            transport.post_stream(url: endpoint, headers: auth_headers, payload:, provider: "openai", &stream)
          else
            transport.post_json(url: endpoint, headers: auth_headers, payload:, provider: "openai")
          end
        end

        private

        def endpoint
          configuration.openai_base_url.presence || DEFAULT_URL
        end

        def auth_headers
          api_key = configuration.openai_api_key
          raise ConfigurationError, "Missing OpenAI API key. Set `Raix.configure { |c| c.openai_api_key = ... }`." if api_key.blank?

          {}.tap do |headers|
            headers["Authorization"] = "Bearer #{api_key}"
            headers["OpenAI-Organization"] = configuration.openai_organization_id if configuration.openai_organization_id.present?
            headers["OpenAI-Project"] = configuration.openai_project_id if configuration.openai_project_id.present?
          end
        end

        def filtered_params(params)
          params.except(:cache_at, :model).compact
        end
      end
    end
  end
end
