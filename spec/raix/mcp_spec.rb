# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe Raix::MCP do
  # let(:mcp_url) { "https://example.com/mcp" }

  # # Build three fake tool definitions for fuller filter testing
  # def build_tool(name)
  #   {
  #     "name" => name.to_s,
  #     "description" => "#{name} tool",
  #     "inputSchema" => {
  #       "type" => "object",
  #       "properties" => {
  #         "input" => { "type" => "string" }
  #       }
  #     }
  #   }
  # end

  # let(:tools_definition) do
  #   %w[echo calculate reverse].map { |n| build_tool(n) }
  # end

  # # Helpers to generate JSON‑RPC responses mimicking an MCP server
  # def build_tools_list_response(tools)
  #   {
  #     jsonrpc: "2.0",
  #     id: SecureRandom.uuid,
  #     result: {
  #       tools:
  #     }
  #   }.to_json
  # end

  # def build_tool_call_response(text)
  #   {
  #     jsonrpc: "2.0",
  #     id: SecureRandom.uuid,
  #     result: {
  #       content: [
  #         {
  #           type: "text",
  #           text:
  #         }
  #       ]
  #     }
  #   }.to_json
  # end

  # before do
  #   # Stub Faraday.post to emulate an MCP server for both tools/list and tools/call requests.
  #   allow(Faraday).to receive(:post) do |_url, body, _headers|
  #     request = JSON.parse(body)

  #     case request["method"]
  #     when "tools/list"
  #       double(body: build_tools_list_response(tools_definition))
  #     when "tools/call"
  #       request.dig("params", "arguments") || {}
  #       double(body: build_tool_call_response("result"))
  #     else
  #       raise "Unexpected MCP method: #{request["method"]}"
  #     end
  #   end
  # end

  # # Define a class that consumes the new Raix::MCP DSL.
  # before do
  #   stub = self # ensure binding for class eval

  #   Object.const_set(:DummyMcpConsumer, Class.new do
  #     include Raix::ChatCompletion
  #     include Raix::MCP

  #     # Declare the remote MCP server (our stubbed endpoint)
  #     mcp stub.mcp_url

  #     def initialize
  #       transcript << { user: "Hello there" }
  #     end
  #   end)
  # end

  # after do
  #   Object.send(:remove_const, :DummyMcpConsumer) if defined?(DummyMcpConsumer)
  #   Object.send(:remove_const, :OnlyConsumer) if defined?(OnlyConsumer)
  #   Object.send(:remove_const, :ExceptConsumer) if defined?(ExceptConsumer)
  # end

  # xit "registers tools from the remote server" do
  #   expect(DummyMcpConsumer.functions.map { |f| f[:name] }).to include(:echo)

  #   dummy = DummyMcpConsumer.new
  #   # tools should include hash with function schema for the echo tool
  #   tool_names = dummy.tools.map { |t| t.dig(:function, :name) }
  #   expect(tool_names).to include(:echo)
  # end

  # xcontext "when using :only filter" do
  #   before do
  #     stub = self
  #     Object.const_set(:OnlyConsumer, Class.new do
  #       include Raix::ChatCompletion
  #       include Raix::MCP

  #       mcp stub.mcp_url, only: [:echo]
  #     end)
  #   end

  #   it "only registers specified tools" do
  #     names = OnlyConsumer.functions.map { |f| f[:name] }
  #     expect(names).to eq([:echo])
  #   end
  # end

  # xcontext "when using :except filter" do
  #   before do
  #     stub = self
  #     Object.const_set(:ExceptConsumer, Class.new do
  #       include Raix::ChatCompletion
  #       include Raix::MCP

  #       mcp stub.mcp_url, except: [:reverse]
  #     end)
  #   end

  #   it "excludes specified tools" do
  #     names = ExceptConsumer.functions.map { |f| f[:name] }
  #     expect(names).to include(:echo, :calculate)
  #     expect(names).not_to include(:reverse)
  #   end
  # end

  # xcontext "transcript records tool call" do
  #   it "stores assistant and tool messages array" do
  #     dummy = DummyMcpConsumer.new
  #     dummy.echo(input: "hi")

  #     entry = dummy.transcript.last
  #     expect(entry).to be_an(Array)
  #     assistant_msg, tool_msg = entry
  #     expect(assistant_msg[:tool_calls].first.dig(:function, :name)).to eq("echo")
  #     expect(tool_msg[:name]).to eq("echo")
  #   end
  # end

  # xcontext "name clash across multiple MCP servers" do
  #   before do
  #     stub = self
  #     Object.const_set(:ClashConsumer, Class.new do
  #       include Raix::ChatCompletion
  #       include Raix::MCP

  #       mcp "https://one.example.com/mcp"
  #       mcp "https://two.example.com/mcp"
  #     end)
  #   end

  #   after { Object.send(:remove_const, :ClashConsumer) if defined?(ClashConsumer) }

  #   it "renames clashing methods with domain prefix" do
  #     names = ClashConsumer.functions.map { |f| f[:name] }
  #     expect(names).to include(:echo)
  #     expect(names.any? { |n| n.to_s.start_with?("two_example_com_echo") }).to be(true)
  #   end
  # end

  context "with live MCP integration" do
    # Use the official GitMCP endpoint for the MCP documentation server
    # NOTE: This server needs to implement the SSE protocol correctly with an endpoint event
    let(:real_mcp_url) { "https://gitmcp.io/modelcontextprotocol/modelcontextprotocol/docs" }

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
      puts "Available GitMCP tools: #{tools.join(", ")}"
    end

    xit "successfully calls a function on the GitMCP server" do
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
      expect(assistant_msg[:tool_calls].first.dig(:function, :name)).to eq(function_name.to_s)

      expect(tool_msg[:role]).to eq("tool")
      expect(tool_msg[:name]).to eq(function_name.to_s)
      expect(tool_msg[:content]).to be_a(String)
    end
  end
end
