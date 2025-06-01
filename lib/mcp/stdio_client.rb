require_relative "tool"
require "json"
require "securerandom"
require "digest"

module Raix
  module MCP
    # Client for communicating with MCP servers via stdio using JSON-RPC.
    class StdioClient
      # Creates a new client with a bidirectional pipe to the MCP server.
      def initialize(*args, env)
        @args = args
        @io = IO.popen(env, args, "w+")
      end

      # Returns available tools from the server.
      def tools
        result = call("tools/list")

        result["tools"].map do |tool_json|
          Tool.from_json(tool_json)
        end
      end

      # Executes a tool with given arguments.
      # Returns text content directly, or JSON-encoded data for other content types.
      def call_tool(name, **arguments)
        result = call("tools/call", name:, arguments:)
        content = result["content"]
        return "" if content.nil? || content.empty?

        # Handle different content formats
        first_item = content.first
        case first_item
        when Hash
          case first_item["type"]
          when "text"
            first_item["text"]
          when "image"
            # Return a structured response for images
            {
              type: "image",
              data: first_item["data"],
              mime_type: first_item["mimeType"] || "image/png"
            }.to_json
          else
            # For any other type, return the item as JSON
            first_item.to_json
          end
        else
          first_item.to_s
        end
      end

      # Closes the connection to the server.
      def close
        @io.close
      end

      def unique_key
        parametrized_args = @args.join(" ").parameterize.underscore
        Digest::SHA256.hexdigest(parametrized_args)[0..7]
      end

      private

      # Sends JSON-RPC request and returns the result.
      def call(method, **params)
        @io.puts({ id: SecureRandom.uuid, method:, params:, jsonrpc: JSONRPC_VERSION }.to_json)
        @io.flush # Ensure data is immediately sent
        message = JSON.parse(@io.gets)
        if (error = message["error"])
          raise ProtocolError, error["message"]
        end

        message["result"]
      end
    end
  end
end
