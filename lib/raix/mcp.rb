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
require "faraday"
require "uri"
require "json"

require_relative "raix/mcp/stdio_client"

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
    PROTOCOL_VERSION = "2024-11-05".freeze # Current supported protocol version
    CONNECTION_TIMEOUT = 10
    OPEN_TIMEOUT = 30

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
      # NOTE TO SELF: NEVER MOCK SERVER RESPONSES! THIS MUST WORK WITH REAL SERVERS!
      def mcp(url, only: nil, except: nil)
        @mcp_servers ||= {}

        return if @mcp_servers.key?(url) # avoid duplicate definitions

        # Connect and initialize the SSE endpoint

        result = Thread::Queue.new
        Thread.new do
          establish_sse_connection(url, result:)
        end
        tools = result.pop

        if tools.empty?
          puts "[MCP DEBUG] No tools found from MCP server at #{url}"
          return nil
        end

        # 3. Register each tool so ChatCompletion#tools picks them up
        # Apply filters
        filtered_tools = if only.present?
                           only_symbols = Array(only).map(&:to_sym)
                           tools.select { |tool| only_symbols.include?(tool["name"].to_sym) }
                         elsif except.present?
                           except_symbols = Array(except).map(&:to_sym)
                           tools.reject { |tool| except_symbols.include?(tool["name"].to_sym) }
                         else
                           tools
                         end

        # Ensure FunctionDispatch is included in the class
        # Explicit include in the class context
        include FunctionDispatch unless included_modules.include?(FunctionDispatch)
        puts "[MCP DEBUG] FunctionDispatch included in #{name}"

        filtered_tools.each do |tool|
          remote_name = tool[:name]
          # TODO: Revisit later whether this much context is needed in the function name
          local_name = "#{url.parameterize.underscore}_#{remote_name}".gsub("https_", "").to_sym

          description  = tool["description"]
          input_schema = tool["inputSchema"] || {}

          # --- register with FunctionDispatch (adds to .functions)
          function(local_name, description, **{}) # placeholder parameters replaced next
          latest_definition = functions.last
          latest_definition[:parameters] = input_schema.deep_symbolize_keys if input_schema.present?

          # --- define an instance method that proxies to the server
          define_method(local_name) do |**arguments|
            arguments ||= {}

            call_id = SecureRandom.uuid
            result = Thread::Queue.new
            Thread.new do
              self.class.establish_sse_connection(url, name: remote_name, arguments:, result:)
            end

            content_item = result.pop

            # Decide what to add to the transcript
            content_text = if content_item.is_a?(Hash) && content_item["type"] == "text"
                             content_item["text"]
                           else
                             content_item.to_json
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

        # Store the URL and tools for future use
        @mcp_servers[url] = { tools: }
      end

      # Establishes an SSE connection to +url+ and returns the JSON‑RPC POST endpoint
      # advertised by the server.  The MCP specification allows two different event
      # formats during initialization:
      #
      # 1. A generic JSON‑RPC *initialize* event (the behaviour previously
      #    implemented):
      #
      #        event: message    (implicit when no explicit event type is given)
      #        data: {"jsonrpc":"2.0","method":"initialize","params":{"endpoint_url":"https://…/rpc"}}
      #
      # 2. A dedicated *endpoint* event, as implemented by the reference
      #    TypeScript SDK and the public GitMCP server used in our test-suite:
      #
      #        event: endpoint\n
      #        data: /rpc\n
      #
      # This method now supports **both** formats.
      #
      # It uses Net::HTTP directly rather than Faraday streaming because the latter
      # does not consistently surface partial body reads across adapters.  The
      # implementation reads the response body incrementally, splitting on the
      # SSE record delimiter (double newline) and processing each event until an
      # endpoint is discovered (or a timeout / connection error occurs).
      def establish_sse_connection(url, name: nil, arguments: {}, result: nil)
        puts "[MCP DEBUG] Establishing MCP connection with URL: #{url}"

        headers = {
          "Accept" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "Connection" => "keep-alive",
          "MCP-Version" => PROTOCOL_VERSION
        }

        endpoint_url = nil
        buffer = ""

        connection = Faraday.new(url:) do |faraday|
          faraday.options.timeout = CONNECTION_TIMEOUT
          faraday.options.open_timeout = OPEN_TIMEOUT
        end

        connection.get do |req|
          req.headers = headers
          req.options.on_data = proc do |chunk, _size|
            buffer << chunk

            # Process complete SSE events (separated by a blank line)
            while (idx = buffer.index("\n\n"))
              event_text = buffer.slice!(0..idx + 1) # include delimiter
              event_type, event_data = parse_sse_fields(event_text)

              case event_type
              when "endpoint"
                # event data is expected to be a plain string with the endpoint
                puts "[MCP DEBUG] Found endpoint event: #{event_data}"
                endpoint_url = build_absolute_url(url, event_data)
                initialize_mcp_connection(connection, endpoint_url)
              when "message"
                puts "[MCP DEBUG] Received message: #{event_data}"
                dispatch_event(event_data, connection, endpoint_url, name, arguments, result)
              else
                puts "[MCP DEBUG] Unexpected event type: #{event_type} with data: #{event_data}"
              end
            end
          end
        end
      end

      # Parses an SSE *event block* (text up to the blank line delimiter) and
      # returns `[event_type, data]` where *event_type* defaults to "message" when
      # no explicit `event:` field is present.  The *data* combines all `data:`
      # lines separated by newlines, as per the SSE specification.
      def parse_sse_fields(event_text)
        event_type = "message"
        data_lines = []

        event_text.each_line do |line|
          case line
          when /^event:\s*(.+)$/
            event_type = Regexp.last_match(1).strip
          when /^data:\s*(.*)$/
            data_lines << Regexp.last_match(1)
          end
        end

        [event_type, data_lines.join("\n").strip]
      end

      # Builds an absolute URL for +candidate+ relative to +base+.
      # If +candidate+ is already absolute, it is returned unchanged.
      def build_absolute_url(base, candidate)
        uri = URI.parse(candidate)
        return candidate if uri.absolute?

        URI.join(base, candidate).to_s
      rescue URI::InvalidURIError
        candidate # fall back to original string
      end

      def initialize_mcp_connection(connection, endpoint_url)
        puts "[MCP DEBUG] Initializing MCP connection with URL: #{endpoint_url}"
        connection.post(endpoint_url) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = {
            jsonrpc: JSONRPC_VERSION,
            id: SecureRandom.uuid,
            method: "initialize",
            params: {
              protocolVersion: PROTOCOL_VERSION,
              capabilities: {
                roots: {
                  listChanged: true
                },
                sampling: {}
              },
              clientInfo: {
                name: "Raix",
                version: Raix::VERSION
              }
            }
          }.to_json
        end
      end

      def dispatch_event(event_data, connection, endpoint_url, name, arguments, result)
        event_data = JSON.parse(event_data, symbolize_names: true)
        case event_data
        in { result: { capabilities: { tools: { listChanged: true } } } }
          puts "[MCP DEBUG] Received listChanged event"
          acknowledge_event(connection, endpoint_url)
          fetch_mcp_tools(connection, endpoint_url)
        in { result: { tools: } }
          puts "[MCP DEBUG] Received tools event: #{tools}"
          if name.present?
            puts "[MCP DEBUG] Calling function: #{name} with params: #{arguments.inspect}"
            remote_dispatch(connection, endpoint_url, name, arguments)
          else
            result << tools # will unblock the pop on the main thread
            connection.close
          end
        in { result: { content: } }
          puts "[MCP DEBUG] Received content event: #{content}"
          result << content # will unblock the pop on the main thread
          connection.close
        else
          puts "[MCP DEBUG] Received unexpected event: #{event_data}"
        end
      end

      def remote_dispatch(connection, endpoint_url, name, arguments)
        connection.post(endpoint_url) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = {
            jsonrpc: JSONRPC_VERSION,
            id: SecureRandom.uuid,
            method: "tools/call",
            params: { name:, arguments: }
          }.to_json
        end
      end

      def acknowledge_event(connection, endpoint_url)
        puts "[MCP DEBUG] Acknowledging event"
        connection.post(endpoint_url) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = {
            jsonrpc: JSONRPC_VERSION,
            method: "notifications/initialized"
          }.to_json
        end
      end

      def fetch_mcp_tools(connection, endpoint_url)
        puts "[MCP DEBUG] Fetching tools"
        connection.post(endpoint_url) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = {
            jsonrpc: JSONRPC_VERSION,
            id: SecureRandom.uuid,
            method: "tools/list",
            params: {}
          }.to_json
        end
      end
    end
  end
end
