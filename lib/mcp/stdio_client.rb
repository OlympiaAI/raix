require_relative "tool"
require "json"
require "securerandom"

module Raix
  module MCP
    # Client for communicating with MCP servers via stdio using JSON-RPC.
    class StdioClient
      # Creates a new client with a bidirectional pipe to the MCP server.
      def initialize(*args, env)
        @io = IO.popen(env, args, "w+")
      end

      # Returns available tools from the server.
      def tools
        result = call("tools/list")

        result["tools"].map do |tool_json|
          Tool.from_json(tool_json)
        end
      end

      # Executes a tool with given arguments, returns text content.
      def call_tool(name, **arguments)
        result = call("tools/call", name:, arguments:)
        unless result.dig("content", 0, "type") == "text"
          raise NotImplementedError, "Only text is supported"
        end

        result.dig("content", 0, "text")
      end

      # Closes the connection to the server.
      def close
        @io.close
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
