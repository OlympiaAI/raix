# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::MCP::StdioClient do
  let(:test_server_path) { File.join(__dir__, "../../support/mcp_server.rb") }
  let(:client) { described_class.new("ruby", test_server_path, {}) }

  before do
    # Ensure the test server exists
    expect(File.exist?(test_server_path)).to be true
  end

  after do
    client&.close
  end

  describe "#initialize" do
    it "creates a new client with a bidirectional pipe" do
      expect(client.instance_variable_get(:@io)).to be_a(IO)
      expect(client.instance_variable_get(:@io)).not_to be_closed
    end

    it "accepts command arguments and environment variables" do
      env = { "TEST_VAR" => "test_value" }
      test_client = described_class.new("ruby", "-e", "puts ENV['TEST_VAR']", env)

      expect(test_client.instance_variable_get(:@io)).to be_a(IO)
      test_client.close
    end
  end

  describe "#tools" do
    it "returns available tools from the server" do
      tools = client.tools

      expect(tools).to be_an(Array)
      expect(tools).not_to be_empty
      expect(tools.first).to be_a(Raix::MCP::Tool)
    end

    it "returns tools with correct attributes" do
      tools = client.tools
      tool = tools.first

      expect(tool.name).to be_a(String)
      expect(tool.description).to be_a(String)
      expect(tool.input_schema).to be_a(Hash)
    end
  end

  describe "#call_tool" do
    let(:tool_name) { "echo" }
    let(:arguments) { { message: "Hello, World!" } }

    it "executes a tool with given arguments and returns text content" do
      result = client.call_tool(tool_name, **arguments)

      expect(result).to be_a(String)
      expect(result).to include("Hello, World!")
    end

    it "handles tools with no arguments" do
      result = client.call_tool("ping")

      expect(result).to be_a(String)
      expect(result).to eq("pong")
    end

    it "handles tools with complex arguments" do
      complex_args = {
        data: {
          items: %w[item1 item2],
          metadata: { key: "value" }
        }
      }

      result = client.call_tool("process_data", **complex_args)
      expect(result).to be_a(String)
      expect(JSON.parse(result)).to include("processed" => true)
    end

    it "handles image content by returning structured JSON" do
      result = client.call_tool("binary_data")
      expect(result).to be_a(String)

      parsed = JSON.parse(result)
      expect(parsed["type"]).to eq("image")
      expect(parsed["data"]).to eq("base64encodeddata")
      expect(parsed["mime_type"]).to eq("image/png")
    end

    it "raises ProtocolError for invalid tool names" do
      expect do
        client.call_tool("nonexistent_tool")
      end.to raise_error(Raix::MCP::ProtocolError)
    end

    it "raises ProtocolError for invalid arguments" do
      expect do
        client.call_tool("echo", invalid_param: "value")
      end.to raise_error(Raix::MCP::ProtocolError)
    end
  end

  describe "#close" do
    it "closes the connection to the server" do
      io = client.instance_variable_get(:@io)
      expect(io).not_to be_closed

      client.close
      expect(io).to be_closed
    end

    it "can be called multiple times safely" do
      client.close
      expect { client.close }.not_to raise_error
    end
  end

  describe "JSON-RPC communication" do
    it "sends properly formatted JSON-RPC requests" do
      # Mock the IO to capture the request
      io_mock = double("IO")
      allow(IO).to receive(:popen).and_return(io_mock)
      allow(io_mock).to receive(:puts)
      allow(io_mock).to receive(:flush)
      allow(io_mock).to receive(:gets).and_return('{"jsonrpc":"2.0","id":"test","result":{"tools":[]}}')
      allow(io_mock).to receive(:close)

      test_client = described_class.new("ruby", test_server_path, {})

      expect(io_mock).to receive(:puts) do |json_string|
        request = JSON.parse(json_string)
        expect(request["jsonrpc"]).to eq("2.0")
        expect(request["method"]).to eq("tools/list")
        expect(request["id"]).to be_a(String)
        expect(request["params"]).to be_a(Hash)
      end

      test_client.tools
      test_client.close
    end

    it "handles JSON-RPC error responses" do
      io_mock = double("IO")
      allow(IO).to receive(:popen).and_return(io_mock)
      allow(io_mock).to receive(:puts)
      allow(io_mock).to receive(:flush)
      allow(io_mock).to receive(:gets).and_return('{"jsonrpc":"2.0","id":"test","error":{"code":-32601,"message":"Method not found"}}')
      allow(io_mock).to receive(:close)

      test_client = described_class.new("ruby", test_server_path, {})

      expect do
        test_client.tools
      end.to raise_error(Raix::MCP::ProtocolError, "Method not found")

      test_client.close
    end
  end

  describe "integration with real MCP server process" do
    it "can communicate with a real subprocess" do
      # This test ensures the actual stdio communication works
      tools = client.tools
      expect(tools).not_to be_empty

      # Test actual tool execution
      result = client.call_tool("echo", message: "Integration test")
      expect(result).to include("Integration test")
    end

    it "handles server startup and shutdown gracefully" do
      # Test that we can create multiple clients
      client1 = described_class.new("ruby", test_server_path, {})
      client2 = described_class.new("ruby", test_server_path, {})

      tools1 = client1.tools
      tools2 = client2.tools

      expect(tools1).not_to be_empty
      expect(tools2).not_to be_empty

      client1.close
      client2.close
    end
  end
end
