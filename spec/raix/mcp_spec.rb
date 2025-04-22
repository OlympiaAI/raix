# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe Raix::MCP do
  let(:mcp_url) { "https://example.com/mcp" }

  # Define a single fake tool exposed by the remote MCP server
  let(:tools_definition) do
    [{
      "name" => "echo",
      "description" => "Echo a given message back to the caller",
      "inputSchema" => {
        "type" => "object",
        "properties" => {
          "message" => { "type" => "string" }
        },
        "required" => ["message"]
      }
    }]
  end

  # Helpers to generate JSON‑RPC responses mimicking an MCP server
  def build_tools_list_response(tools)
    {
      jsonrpc: "2.0",
      id: SecureRandom.uuid,
      result: {
        tools:
      }
    }.to_json
  end

  def build_tool_call_response(text)
    {
      jsonrpc: "2.0",
      id: SecureRandom.uuid,
      result: {
        content: [
          {
            type: "text",
            text:
          }
        ]
      }
    }.to_json
  end

  before do
    # Stub Faraday.post to emulate an MCP server for both tools/list and tools/call requests.
    allow(Faraday).to receive(:post) do |_url, body, _headers|
      request = JSON.parse(body)

      case request["method"]
      when "tools/list"
        double(body: build_tools_list_response(tools_definition))
      when "tools/call"
        arguments = request.dig("params", "arguments") || {}
        message   = arguments["message"] || arguments[:message] || ""
        double(body: build_tool_call_response("Echo: #{message}"))
      else
        raise "Unexpected MCP method: #{request["method"]}"
      end
    end
  end

  # Define a class that consumes the new Raix::MCP DSL.
  before do
    stub = self # ensure binding for class eval

    Object.const_set(:DummyMcpConsumer, Class.new do
      include Raix::ChatCompletion
      include Raix::MCP

      # Declare the remote MCP server (our stubbed endpoint)
      mcp stub.mcp_url

      def initialize
        transcript << { user: "Hello there" }
      end
    end)
  end

  after do
    Object.send(:remove_const, :DummyMcpConsumer) if defined?(DummyMcpConsumer)
  end

  it "registers tools from the remote server" do
    expect(DummyMcpConsumer.functions.map { |f| f[:name] }).to include(:echo)

    dummy = DummyMcpConsumer.new
    # tools should include hash with function schema for the echo tool
    tool_names = dummy.tools.map { |t| t.dig(:function, :name) }
    expect(tool_names).to include(:echo)
  end

  it "defines proxy methods that dispatch via MCP" do
    dummy = DummyMcpConsumer.new

    result = dummy.echo(message: "Hello")

    expect(result).to eq("Echo: Hello")

    # Verify that the transcript was updated with an array containing assistant & tool messages
    new_entry = dummy.transcript.last
    expect(new_entry).to be_an(Array)

    assistant_msg, tool_msg = new_entry

    expect(assistant_msg[:role]).to eq("assistant")
    expect(assistant_msg[:tool_calls].first.dig(:function, :name)).to eq("echo")

    expect(tool_msg[:role]).to eq("tool")
    expect(tool_msg[:name]).to eq("echo")
    expect(tool_msg[:content]).to eq("Echo: Hello")
  end
end
