# frozen_string_literal: true

require "active_support/core_ext/module/delegation"

module Raix
  module MessageAdapters
    # Transforms messages into the format expected by the OpenAI API
    class Base
      attr_accessor :context

      delegate :cache_at, :model, to: :context

      def initialize(context)
        @context = context
      end

      def transform(message)
        return message if message[:role].present?

        if message[:function].present?
          { role: "assistant", name: message.dig(:function, :name), content: message.dig(:function, :arguments).to_json }
        elsif message[:result].present?
          { role: "function", name: message[:name], content: message[:result] }
        else
          content(message)
        end
      end

      protected

      def content(message)
        case message
        in { system: content }
          { role: "system", content: }
        in { user: content }
          { role: "user", content: }
        in { assistant: content }
          { role: "assistant", content: }
        else
          raise ArgumentError, "Invalid message format: #{message.inspect}"
        end.tap do |msg|
          # convert to anthropic multipart format if model is claude-3 and cache_at is set
          if model.to_s.include?("anthropic/claude-3") && cache_at && msg[:content].to_s.length > cache_at.to_i
            msg[:content] = [{ type: "text", text: msg[:content], cache_control: { type: "ephemeral" } }]
          end
        end
      end
    end
  end
end
