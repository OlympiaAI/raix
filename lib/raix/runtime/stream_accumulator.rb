# frozen_string_literal: true

module Raix
  module Runtime
    # Reconstructs a final OpenAI-style assistant message from streaming deltas.
    class StreamAccumulator
      def initialize
        @content = +""
        @tool_calls = {}
        @finish_reason = nil
        @usage = nil
      end

      def consume(chunk)
        @usage = chunk["usage"] if chunk["usage"].is_a?(Hash)

        choice = chunk.dig("choices", 0) || {}
        delta = choice["delta"] || {}
        @finish_reason = choice["finish_reason"] if choice.key?("finish_reason")

        append_content(delta["content"])
        append_tool_calls(delta["tool_calls"])
      end

      def envelope
        tool_calls = @tool_calls.keys.sort.map { |index| @tool_calls[index] }

        {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => @content.empty? ? nil : @content,
                "tool_calls" => tool_calls.empty? ? nil : tool_calls
              },
              "finish_reason" => @finish_reason || (tool_calls.any? ? "tool_calls" : "stop")
            }
          ],
          "usage" => @usage
        }
      end

      private

      def append_content(content)
        @content << content.to_s if content
      end

      def append_tool_calls(tool_calls)
        return unless tool_calls.is_a?(Array)

        tool_calls.each do |call|
          index = call["index"] || 0
          @tool_calls[index] ||= {
            "id" => call["id"],
            "type" => call["type"] || "function",
            "function" => { "name" => +"", "arguments" => +"" }
          }

          existing = @tool_calls[index]
          existing["id"] ||= call["id"]
          existing["type"] ||= call["type"] if call["type"]

          function = call["function"] || {}
          existing_function = existing["function"] ||= {}
          existing_function["name"] ||= +""
          existing_function["arguments"] ||= +""
          existing_function["name"] << function["name"].to_s if function["name"]
          existing_function["arguments"] << function["arguments"].to_s if function["arguments"]
        end
      end
    end
  end
end
