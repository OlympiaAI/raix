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

require "active_support/concern"
require "active_support/inflector"
require "securerandom"
require "uri"

require_relative "../mcp/sse_client"
require_relative "../mcp/stdio_client"

module Raix
  # Model Context Protocol integration for Raix
  #
  # Allows declaring MCP servers with a simple DSL that automatically:
  # - Queries tools from the remote server
  # - Exposes each tool as a function callable by LLMs
  # - Handles transcript recording and response processing
  module MCP
    extend ActiveSupport::Concern

    # Error raised when there's a protocol-level error in MCP communication
    class ProtocolError < StandardError; end

    JSONRPC_VERSION = "2.0".freeze

    class_methods do
      # Declare an MCP server by URL, using the SSE transport.
      #
      #   sse_mcp "https://server.example.com/sse",
      #           headers: { "Authorization" => "Bearer <token>" },
      #           only: [:get_issue]
      #
      def sse_mcp(url, headers: {}, only: nil, except: nil)
        mcp(only:, except:, client: MCP::SseClient.new(url, headers:))
      end

      # Declare an MCP server by command line arguments, and environment variables  ,
      # using the stdio transport.
      #
      #   stdio_mcp "docker", "run", "-i", "--rm",
      #             "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
      #             "ghcr.io/github/github-mcp-server",
      #             env: { GITHUB_PERSONAL_ACCESS_TOKEN: "${input:github_token}" },
      #             only: [:github_search]
      #
      def stdio_mcp(*args, env: {}, only: nil, except: nil)
        mcp(only:, except:, client: MCP::StdioClient.new(*args, env))
      end

      # Declare an MCP server, using the given client.
      #
      #   mcp client: MCP::SseClient.new("https://server.example.com/sse")
      #
      # This will automatically:
      #   • query `tools/list` on the server
      #   • register each remote tool with FunctionDispatch so that the
      #     OpenAI / OpenRouter request body includes its JSON‑Schema
      #   • define an instance method for each tool that forwards the
      #     call to the server and appends the proper messages to the
      #     transcript.
      # NOTE TO SELF: NEVER MOCK SERVER RESPONSES! THIS MUST WORK WITH REAL SERVERS!
      def mcp(client:, only: nil, except: nil)
        @mcp_servers ||= {}

        return if @mcp_servers.key?(client.unique_key) # avoid duplicate definitions

        # Fetch tools
        tools = client.tools

        if tools.empty?
          # puts "[MCP DEBUG] No tools found from MCP server at #{url}"
          client.close
          return nil
        end

        # Apply filters
        filtered_tools = if only.present?
                           only_symbols = Array(only).map(&:to_sym)
                           tools.select { |tool| only_symbols.include?(tool.name.to_sym) }
                         elsif except.present?
                           except_symbols = Array(except).map(&:to_sym)
                           tools.reject { |tool| except_symbols.include?(tool.name.to_sym) }
                         else
                           tools
                         end

        # Ensure FunctionDispatch is included in the class
        include FunctionDispatch unless included_modules.include?(FunctionDispatch)
        # puts "[MCP DEBUG] FunctionDispatch included in #{name}"

        filtered_tools.each do |tool|
          remote_name = tool.name
          # TODO: Revisit later whether this much context is needed in the function name
          local_name = "#{client.unique_key}_#{remote_name}".to_sym

          description = tool.description
          input_schema = tool.input_schema || {}

          # --- register with FunctionDispatch (adds to .functions)
          function(local_name, description, **{}) # placeholder parameters replaced next
          latest_definition = functions.last
          latest_definition[:parameters] = input_schema.deep_symbolize_keys || {}

          # Required by OpenAI
          latest_definition[:parameters][:properties] ||= {}

          # Store the schema for type coercion
          tool_schemas = @tool_schemas ||= {}
          tool_schemas[local_name] = input_schema

          # --- define an instance method that proxies to the server
          define_method(local_name) do |arguments, _cache|
            arguments ||= {}

            # Coerce argument types based on the input schema
            stored_schema = self.class.instance_variable_get(:@tool_schemas)&.dig(local_name)
            coerced_arguments = coerce_arguments(arguments, stored_schema)

            content_text = client.call_tool(remote_name, **coerced_arguments)
            call_id = SecureRandom.uuid

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
                      name: remote_name,
                      arguments: arguments.to_json
                    }
                  }
                ]
              },
              {
                role: "tool",
                tool_call_id: call_id,
                name: remote_name,
                content: content_text
              }
            ]

            # Continue the chat loop if requested (same semantics as FunctionDispatch)
            chat_completion(**chat_completion_args) if loop

            content_text
          end
        end

        # Store the URL, tools, and client for future use
        @mcp_servers[client.unique_key] = { tools: filtered_tools, client: }
      end
    end

    private

    # Coerce argument types based on the JSON schema
    def coerce_arguments(arguments, schema)
      return arguments unless schema.is_a?(Hash) && schema["properties"].is_a?(Hash)

      coerced = {}
      schema["properties"].each do |key, prop_schema|
        value = arguments[key] || arguments[key.to_sym]
        next if value.nil?

        coerced[key] = case prop_schema["type"]
                       when "number", "integer"
                         if value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/)
                           prop_schema["type"] == "integer" ? value.to_i : value.to_f
                         else
                           value
                         end
                       when "boolean"
                         case value
                         when "true", true then true
                         when "false", false then false
                         else value
                         end
                       when "array"
                         begin
                           value.is_a?(String) ? JSON.parse(value) : value
                         rescue JSON::ParserError
                           value
                         end
                       when "object"
                         begin
                           value.is_a?(String) ? JSON.parse(value) : value
                         rescue JSON::ParserError
                           value
                         end
                       else
                         value
                       end
      end

      # Include any additional arguments not in the schema
      arguments.each do |key, value|
        key_str = key.to_s
        coerced[key_str] = value unless coerced.key?(key_str)
      end

      coerced.with_indifferent_access
    end
  end
end
