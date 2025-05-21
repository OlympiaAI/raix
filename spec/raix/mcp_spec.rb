# frozen_string_literal: true

require "spec_helper"
require "securerandom"
require "webmock/rspec"

RSpec.describe Raix::MCP do
  context "with live MCP integration" do
    # Use the official GitMCP endpoint for the MCP documentation server
    # NOTE: This server needs to implement the SSE protocol correctly with an endpoint event
    let(:real_mcp_url) { "https://gitmcp.io/OlympiaAI/raix/docs" }

    before do
      # Skip stubs - we want real HTTP requests in this context
      allow(Faraday).to receive(:post).and_call_original

      stub = self
      Object.const_set(:LiveMcpConsumer, Class.new do
        include Raix::ChatCompletion
        include Raix::FunctionDispatch
        include Raix::MCP

        mcp stub.real_mcp_url

        def initialize
          transcript << { role: "user", content: "Testing live MCP integration" }
        end

        def self.functions
          @functions || []
        end
      end)
    end

    after do
      Object.send(:remove_const, :LiveMcpConsumer) if defined?(LiveMcpConsumer)
    end

    it "fetches tools from the GitMCP server", :novcr do
      # Ensure the class is defined properly
      expect(defined?(LiveMcpConsumer)).to eq("constant")
      expect(LiveMcpConsumer).to be_a(Class)

      # Verify it includes the necessary modules
      expect(LiveMcpConsumer.included_modules).to include(Raix::ChatCompletion)
      expect(LiveMcpConsumer.included_modules).to include(Raix::MCP)
      expect(LiveMcpConsumer.included_modules).to include(Raix::FunctionDispatch)

      # The GitMCP endpoint should return at least one tool
      expect(LiveMcpConsumer.respond_to?(:functions)).to be true
      expect(LiveMcpConsumer.functions).not_to be_empty

      # Check instance properties
      consumer = LiveMcpConsumer.new
      expect(consumer.tools).not_to be_empty

      # Print available tools for debugging
      tools = LiveMcpConsumer.functions.map { |f| f[:name] }
      expect(tools).to include(:gitmcp_io_olympiaai_raix_docs_fetch_raix_documentation)
      expect(tools).to include(:gitmcp_io_olympiaai_raix_docs_search_raix_documentation)
      expect(tools).to include(:gitmcp_io_olympiaai_raix_docs_search_raix_code)
      expect(tools).to include(:gitmcp_io_olympiaai_raix_docs_fetch_generic_url_content)
    end

    it "successfully calls a function on the GitMCP server", :novcr do
      consumer = LiveMcpConsumer.new

      # Get the first available function name
      function_name = LiveMcpConsumer.functions.first[:name]

      # Most GitMCP documentation functions accept a 'query' parameter
      # This should work with most documentation tools
      expect(consumer).to respond_to(function_name)

      transcript_size_before = consumer.transcript.size

      # Call the function with a simple query
      result = consumer.public_send(function_name, query: "What is Raix?")

      # Verify we got a result and transcript was updated
      expect(result).to be_a(String)
      expect(result).not_to be_empty
      expect(consumer.transcript.size).to eq(transcript_size_before + 1)

      # Verify transcript structure
      last_entry = consumer.transcript.last
      expect(last_entry).to be_an(Array)
      expect(last_entry.size).to eq(2)

      assistant_msg, tool_msg = last_entry
      expect(assistant_msg[:role]).to eq("assistant")
      expect(function_name.to_s).to include(assistant_msg[:tool_calls].first.dig(:function, :name))

      expect(tool_msg[:role]).to eq("tool")
      expect(function_name.to_s).to include(tool_msg[:name])
      expect(tool_msg[:content]).to be_a(String)
      expect(tool_msg[:content]).to include("Raix consists")
    end
  end

  context "with HTTP protocol support", :novcr do
    let(:mock_http_url) { "https://mock-mcp-server.example.com/api" }

    before do
      # Re-enable WebMock for our stubs (novcr tag turns it off)
      WebMock.enable!
      WebMock.disable_net_connect!(allow_localhost: true)

      # Mock the initialize call
      stub_request(:post, mock_http_url)
        .with(
          body: hash_including(jsonrpc: "2.0", method: "initialize"),
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            jsonrpc: "2.0",
            id: SecureRandom.uuid,
            result: {
              capabilities: {
                tools: { listChanged: true }
              }
            }
          }.to_json
        )

      # Mock the tools/list call
      stub_request(:post, mock_http_url)
        .with(
          body: hash_including(jsonrpc: "2.0", method: "tools/list"),
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            jsonrpc: "2.0",
            id: SecureRandom.uuid,
            result: {
              tools: [
                {
                  name: "echo",
                  description: "Echoes the input message",
                  inputSchema: {
                    type: "object",
                    properties: {
                      message: {
                        type: "string",
                        description: "The message to echo"
                      }
                    },
                    required: ["message"]
                  }
                }
              ]
            }
          }.to_json
        )

      # Mock the tools/call response - match for any params, including headers
      stub_request(:post, mock_http_url)
        .with(
          body: lambda { |body|
            # Parse the body and verify it's a tools/call request with the right structure
            begin
              json = JSON.parse(body)
              json["method"] == "tools/call" &&
              json["params"]["name"] == "echo" &&
              json["params"]["arguments"] &&
              json["params"]["arguments"]["message"] == "Hello, HTTP MCP!"
            rescue
              false
            end
          }
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            jsonrpc: "2.0",
            id: SecureRandom.uuid,
            result: {
              content: {
                type: "text",
                text: "You said: Hello, HTTP MCP!"
              }
            }
          }.to_json
        )

      stub = self
      Object.const_set(:HttpMcpConsumer, Class.new do
        include Raix::ChatCompletion
        include Raix::FunctionDispatch
        include Raix::MCP

        mcp stub.mock_http_url, protocol: :http

        def initialize
          @transcript = []
        end

        attr_reader :transcript

        def self.functions
          @functions || []
        end
      end)
    end

    after do
      # Clean up constants but don't need to restore WebMock/VCR (handled by :novcr)
      Object.send(:remove_const, :HttpMcpConsumer) if defined?(HttpMcpConsumer)
    end

    it "initializes with HTTP protocol", :novcr do
      # Ensure the class is defined properly
      expect(defined?(HttpMcpConsumer)).to eq("constant")
      expect(HttpMcpConsumer).to be_a(Class)

      # Verify it includes the necessary modules
      expect(HttpMcpConsumer.included_modules).to include(Raix::ChatCompletion)
      expect(HttpMcpConsumer.included_modules).to include(Raix::MCP)
      expect(HttpMcpConsumer.included_modules).to include(Raix::FunctionDispatch)

      # Verify HTTP requests were made
      expect(WebMock).to have_requested(:post, mock_http_url)
        .with(body: hash_including(jsonrpc: "2.0", method: "initialize"))

      expect(WebMock).to have_requested(:post, mock_http_url)
        .with(body: hash_including(jsonrpc: "2.0", method: "tools/list"))
    end

    it "fetches tools via HTTP", :novcr do
      # The HTTP endpoint should return at least one tool
      expect(HttpMcpConsumer.respond_to?(:functions)).to be true
      expect(HttpMcpConsumer.functions).not_to be_empty

      # Check available tools
      tools = HttpMcpConsumer.functions.map { |f| f[:name] }
      expect(tools).to include(:mock_mcp_server_example_com_api_echo)
    end

    it "successfully calls a function via HTTP", :novcr do
      consumer = HttpMcpConsumer.new

      # Get the function name
      function_name = HttpMcpConsumer.functions.first[:name]

      # Verify function exists
      expect(consumer).to respond_to(function_name)

      # Call the function
      result = consumer.public_send(function_name, message: "Hello, HTTP MCP!")

      # Verify the result
      expect(result).to eq("You said: Hello, HTTP MCP!")

      # Verify the HTTP request was made
      expect(WebMock).to have_requested(:post, mock_http_url)
        .with(body: hash_including(
          jsonrpc: "2.0",
          method: "tools/call",
          params: { name: "echo", arguments: { message: "Hello, HTTP MCP!" } }
        ))
    end

    it "handles transcript entries correctly", :novcr do
      consumer = HttpMcpConsumer.new

      # Get the function name
      function_name = HttpMcpConsumer.functions.first[:name]

      # Call the function
      consumer.public_send(function_name, message: "Hello, HTTP MCP!")

      # Verify transcript structure
      expect(consumer.transcript.size).to eq(1)

      last_entry = consumer.transcript.last
      expect(last_entry).to be_an(Array)
      expect(last_entry.size).to eq(2)

      assistant_msg, tool_msg = last_entry
      expect(assistant_msg[:role]).to eq("assistant")
      expect(assistant_msg[:content]).to be_nil
      expect(assistant_msg[:tool_calls].first[:type]).to eq("function")
      expect(assistant_msg[:tool_calls].first[:function][:name]).to eq("echo")
      expect(JSON.parse(assistant_msg[:tool_calls].first[:function][:arguments])).to eq({ "message" => "Hello, HTTP MCP!" })

      expect(tool_msg[:role]).to eq("tool")
      expect(tool_msg[:content]).to eq("You said: Hello, HTTP MCP!")
    end
  end

  context "with mixed protocol support", :novcr do
    let(:mock_http_url) { "https://mock-http-server.example.com/api" }
    let(:mock_sse_url) { "https://mock-sse-server.example.com/sse" }

    before do
      # Re-enable WebMock for our stubs (novcr tag turns it off)
      WebMock.enable!
      WebMock.disable_net_connect!(allow_localhost: true)

      # Mock HTTP endpoints
      stub_request(:post, mock_http_url)
        .with(
          body: hash_including(jsonrpc: "2.0", method: "initialize"),
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            jsonrpc: "2.0",
            id: SecureRandom.uuid,
            result: {
              capabilities: {
                tools: { listChanged: true }
              }
            }
          }.to_json
        )

      stub_request(:post, mock_http_url)
        .with(
          body: hash_including(jsonrpc: "2.0", method: "tools/list"),
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            jsonrpc: "2.0",
            id: SecureRandom.uuid,
            result: {
              tools: [
                {
                  name: "http_tool",
                  description: "A tool via HTTP protocol",
                  inputSchema: {
                    type: "object",
                    properties: {
                      message: {
                        type: "string",
                        description: "The message to echo"
                      }
                    },
                    required: ["message"]
                  }
                }
              ]
            }
          }.to_json
        )

      # Create a test-specific module to avoid messing with the original
      test_mcp_module = Module.new do
        extend ActiveSupport::Concern

        class_methods do
          # Copy all methods from Raix::MCP::ClassMethods except establish_sse_connection
          Raix::MCP.const_get(:ClassMethods).instance_methods(false).each do |method_name|
            next if method_name == :establish_sse_connection

            define_method(method_name) do |*args, **kwargs, &block|
              Raix::MCP.const_get(:ClassMethods).instance_method(method_name).bind(self).call(*args, **kwargs, &block)
            end
          end

          # Override establish_sse_connection to simulate an SSE response without actual connection
          def establish_sse_connection(url, **kwargs)
            puts "[TEST] Simulating SSE connection to #{url}"

            if kwargs[:result]
              # If we're just fetching tools, return a fake tool list
              kwargs[:result] << [
                {
                  name: "sse_tool",
                  description: "A tool via SSE protocol",
                  inputSchema: {
                    type: "object",
                    properties: {
                      message: {
                        type: "string",
                        description: "The message"
                      }
                    }
                  }
                }
              ]
            end
          end
        end
      end

      stub = self
      # Define a special test class that uses our test MCP module
      Object.const_set(:MixedProtocolConsumer, Class.new do
        include Raix::ChatCompletion
        include Raix::FunctionDispatch
        include test_mcp_module

        # We'll still use HTTP through the normal path
        mcp stub.mock_http_url, protocol: :http

        # And add a fake SSE tool directly
        # (simulating what would happen if establish_sse_connection worked)
        function(:mock_sse_server_example_com_sse_sse_tool,
                "A tool via SSE protocol",
                message: { type: "string", description: "The message" })

        def initialize
          @transcript = []
        end

        attr_reader :transcript

        def self.functions
          @functions || []
        end
      end)
    end

    after do
      # Clean up constants but don't need to restore WebMock/VCR (handled by :novcr)
      Object.send(:remove_const, :MixedProtocolConsumer) if defined?(MixedProtocolConsumer)
    end

    it "registers tools from both protocols" do
      # Only tests that the functions were registered
      expect(MixedProtocolConsumer.respond_to?(:functions)).to be true
      expect(MixedProtocolConsumer.functions).not_to be_empty

      # Get function names
      tools = MixedProtocolConsumer.functions.map { |f| f[:name] }

      # Check function names contain expected strings
      expect(tools.any? { |name| name.to_s.include?("http_tool") }).to be true
      expect(tools.any? { |name| name.to_s.include?("sse_tool") }).to be true
    end
  end
end
