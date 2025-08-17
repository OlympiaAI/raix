# frozen_string_literal: true

module Raix
  module Providers
    # A wrapper around the OpenRouter client interface to make it compatible with the provider interface.
    class OpenRouterProvider
      attr_reader :client

      def initialize(client)
        @client = client
      end

      def request(params:, model:, messages:)
        params = params.dup

        # max_completion_tokens is not supported by OpenRouter
        params.delete(:max_completion_tokens)

        retry_count = 0

        params.delete(:temperature) if model.start_with?("openai/o") || model.include?("gpt-5")

        stream = params.delete(:stream)

        begin
          client.complete(messages, model:, extras: params.compact, stream:)
        rescue ::OpenRouter::ServerError => e
          if e.message.include?("retry")
            warn "Retrying OpenRouter request... (#{retry_count} attempts) #{e.message}"
            retry_count += 1
            sleep 1 * retry_count # backoff
            retry if retry_count < 5
          end

          raise e
        end
      end
    end
  end
end
