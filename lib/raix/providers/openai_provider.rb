# frozen_string_literal: true

module Raix
  module Providers
    # A wrapper around the OpenAI client to make it compatible with the provider interface.
    class OpenAIProvider
      attr_reader :client

      def initialize(client)
        @client = client
      end

      def request(params:, model:, messages:)
        params = params.dup

        if params[:prediction]
          params.delete(:max_completion_tokens)
        else
          params[:max_completion_tokens] ||= params[:max_tokens]
          params.delete(:max_tokens)
        end

        params[:stream_options] = { include_usage: true } if params[:stream]

        params.delete(:temperature) if model.start_with?("o") || model.include?("gpt-5")

        client.chat(parameters: params.compact.merge(model:, messages:))
      end
    end
  end
end
