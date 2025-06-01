# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe Raix::MCP do
  context "with live SSE MCP server" do
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

        sse_mcp stub.real_mcp_url

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

      unique_key_hash = "7159ed50"
      expect(tools).to include(:"#{unique_key_hash}_fetch_raix_documentation")
      expect(tools).to include(:"#{unique_key_hash}_search_raix_documentation")
      expect(tools).to include(:"#{unique_key_hash}_search_raix_code")
      expect(tools).to include(:"#{unique_key_hash}_fetch_generic_url_content")
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
      result = consumer.public_send(function_name, { query: "What is Raix?" }, nil)

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
end
