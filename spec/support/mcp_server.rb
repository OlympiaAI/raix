#!/usr/bin/env ruby
# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength

require "json"

# Test MCP Server implementing the Model Context Protocol over stdio transport
# This server provides several test tools for validating the StdioClient functionality
class TestMCPServer
  JSONRPC_VERSION = "2.0"

  def initialize
    $stdout.sync = true # Enable auto-flushing for immediate output
    @tools = build_tools
  end

  def run
    # Read JSON-RPC requests from stdin and respond on stdout
    while (line = $stdin.gets)
      begin
        request = JSON.parse(line.strip)
        response = handle_request(request)
        puts response.to_json if response
      rescue JSON::ParserError => e
        error_response = create_error_response(nil, -32_700, "Parse error: #{e.message}")
        puts error_response.to_json
      rescue StandardError => e
        error_response = create_error_response(request&.dig("id"), -32_603, "Internal error: #{e.message}")
        puts error_response.to_json
      end
    end
  end

  private

  def create_response(id:, result: nil, error: nil)
    {
      jsonrpc: JSONRPC_VERSION,
      id:,
      result:,
      error:
    }.compact
  end

  def create_error_response(id, code, message)
    create_response(id:, error: { code:, message: })
  end

  def handle_request(request)
    method = request["method"]
    params = request["params"] || {}
    id = request["id"]

    case method
    when "tools/list"
      handle_tools_list(id)
    when "tools/call"
      handle_tools_call(id, params)
    else
      create_error_response(id, -32_601, "Method not found: #{method}")
    end
  end

  def handle_tools_list(id)
    tools_without_handlers = @tools.values.map do |tool|
      tool.reject { |key, _| key == "handler" }
    end
    create_response(id:, result: { tools: tools_without_handlers })
  end

  def handle_tools_call(id, params)
    tool_name = params["name"]
    arguments = params["arguments"] || {}

    tool = @tools[tool_name]
    unless tool
      return create_error_response(id, -32_602, "Unknown tool: #{tool_name}")
    end

    begin
      content = tool["handler"].call(arguments)
      create_response(id:, result: { content: })
    rescue ArgumentError => e
      create_error_response(id, -32_602, "Invalid parameters: #{e.message}")
    end
  end

  def build_tools
    {
      "ping" => {
        "name" => "ping",
        "description" => "Returns 'pong' - useful for testing connectivity",
        "inputSchema" => {
          "type" => "object",
          "properties" => {},
          "required" => []
        },
        "handler" => ->(_args) { [{ type: "text", text: "pong" }] }
      },
      "echo" => {
        "name" => "echo",
        "description" => "Echoes back the provided message",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "message" => {
              "type" => "string",
              "description" => "The message to echo back"
            }
          },
          "required" => ["message"]
        },
        "handler" => lambda { |args|
          raise ArgumentError, "Missing required parameter: message" unless args["message"]

          [{ type: "text", text: args["message"] }]
        }
      },
      "process_data" => {
        "name" => "process_data",
        "description" => "Processes complex data structures",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "data" => {
              "type" => "object",
              "description" => "Complex data to process"
            }
          },
          "required" => ["data"]
        },
        "handler" => lambda { |args|
          raise ArgumentError, "Missing required parameter: data" unless args["data"]

          [{
            type: "text",
            text: JSON.generate({ processed: true, original: args["data"] })
          }]
        }
      },
      "binary_data" => {
        "name" => "binary_data",
        "description" => "Returns binary data (for testing non-text content)",
        "inputSchema" => {
          "type" => "object",
          "properties" => {},
          "required" => []
        },
        "handler" => ->(_args) { [{ type: "image", data: "base64encodeddata" }] }
      }
    }
  end
end

# Run the server if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  server = TestMCPServer.new
  server.run
end

# rubocop:enable Metrics/ClassLength
