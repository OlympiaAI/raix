# frozen_string_literal: true

# Simple integration layer that lets Raix classes declare an MCP server
# with a single DSL call:
#
#   mcp "https://my-server.example.com/sse"
#
# The concern fetches the remote server's tool list (via JSON‑RPC 2.0
# `tools/list`) and exposes each remote tool as if it were an inline
# `function` declared with Raix::FunctionDispatch.  When the tool is
# invoked by the model, the generated instance method forwards the
# request to the remote server using `tools/call`, captures the result,
# and appends the appropriate messages to the transcript so that the
# conversation history stays consistent.
#
# NOTE: This is deliberately minimal – it assumes the server accepts
# HTTP POST requests at the provided URL and responds with standard
# JSON‑RPC bodies.  Streaming, SSE transports, authentication, and other
# advanced MCP features can be layered on later.
#
# Dependencies: relies on Faraday (already used elsewhere in Raix via
# OpenRouter) and SecureRandom.

require "active_support/concern"
require "securerandom"
require "faraday"

module Raix
  module MCP
    extend ActiveSupport::Concern

    JSONRPC_VERSION = "2.0"

    class_methods do
      # Declare an MCP server by URL.
      #
      #   mcp "https://server.example.com/sse"
      #
      # This will automatically:
      #   • query `tools/list` on the server
      #   • register each remote tool with FunctionDispatch so that the
      #     OpenAI / OpenRouter request body includes its JSON‑Schema
      #   • define an instance method for each tool that forwards the
      #     call to the server and appends the proper messages to the
      #     transcript.
      def mcp(url)
        @mcp_servers ||= {}

        return if @mcp_servers.key?(url) # avoid duplicate definitions

        # 1. Discover remote tools
        tools = fetch_mcp_tools(url)

        # 2. Register each tool so ChatCompletion#tools picks them up
        tools.each do |tool|
          name         = tool["name"].to_sym
          description  = tool["description"]
          input_schema = tool["inputSchema"] || {}

          # --- register with FunctionDispatch (adds to .functions)
          include FunctionDispatch unless ancestors.include?(FunctionDispatch)

          function(name, description, **{}) # dummy to allocate
          # Overwrite the last added definition with remote schema
          latest_definition = functions.last
          latest_definition[:parameters] = input_schema.deep_symbolize_keys if input_schema.present?

          # --- define an instance method that proxies to the server
          define_method(name) do |arguments|
            arguments ||= {}

            call_id = SecureRandom.uuid[0, 23]

            # Perform JSON‑RPC `tools/call`
            payload = {
              jsonrpc: JSONRPC_VERSION,
              id: call_id,
              method: "tools/call",
              params: {
                name: name.to_s,
                arguments:
              }
            }

            response_body = Faraday.post(url, payload.to_json, "Content-Type" => "application/json").body
            parsed        = begin
              JSON.parse(response_body)
            rescue StandardError
              {}
            end
            result = parsed["result"] || {}

            # Extract simple text content if available – otherwise fall back to full JSON
            content_item = (result["content"] || []).first
            content_text = if content_item.is_a?(Hash) && content_item["type"] == "text"
                             content_item["text"]
                           else
                             result.to_json
                           end

            # Mirror FunctionDispatch transcript behaviour
            transcript << [
              {
                role: "assistant",
                content: nil,
                tool_calls: [
                  {
                    id: call_id,
                    type: "function",
                    function: {
                      name: name.to_s,
                      arguments: arguments.to_json
                    }
                  }
                ]
              },
              {
                role: "tool",
                tool_call_id: call_id,
                name: name.to_s,
                content: content_text
              }
            ]

            # Continue the chat loop if requested (same semantics as FunctionDispatch)
            chat_completion(**chat_completion_args) if loop

            content_text
          end
        end

        @mcp_servers[url] = tools
      end

      private

      def fetch_mcp_tools(url)
        payload = {
          jsonrpc: JSONRPC_VERSION,
          id: SecureRandom.uuid,
          method: "tools/list",
          params: {}
        }

        response = Faraday.post(url, payload.to_json, "Content-Type" => "application/json")
        body     = begin
          JSON.parse(response.body)
        rescue StandardError
          {}
        end
        body.dig("result", "tools") || []
      rescue Faraday::Error => e
        warn "[MCP] Failed to fetch tools from #{url}: #{e.message}"
        []
      end
    end
  end
end
