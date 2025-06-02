require_relative "tool"
require "json"
require "securerandom"
require "faraday"
require "uri"
require "digest"

module Raix
  module MCP
    # Client for communicating with MCP servers via Server-Sent Events (SSE).
    class SseClient
      PROTOCOL_VERSION = "2024-11-05".freeze
      CONNECTION_TIMEOUT = 10
      OPEN_TIMEOUT = 30

      # Creates a new client and establishes SSE connection to discover the JSON-RPC endpoint.
      #
      # @param url [String] the SSE endpoint URL
      def initialize(url, headers: {})
        @url = url
        @endpoint_url = nil
        @sse_thread = nil
        @event_queue = Thread::Queue.new
        @buffer = ""
        @closed = false
        @headers = headers

        # Start the SSE connection and discover endpoint
        establish_sse_connection
      end

      # Returns available tools from the server.
      def tools
        @tools ||= begin
          request_id = SecureRandom.uuid
          send_json_rpc(request_id, "tools/list", {})

          # Wait for response through SSE
          response = wait_for_response(request_id)
          response[:tools].map do |tool_json|
            Tool.from_json(tool_json)
          end
        end
      end

      # Executes a tool with given arguments.
      # Returns text content directly, or JSON-encoded data for other content types.
      def call_tool(name, **arguments)
        request_id = SecureRandom.uuid
        send_json_rpc(request_id, "tools/call", name:, arguments:)

        # Wait for response through SSE
        response = wait_for_response(request_id)
        content = response[:content]
        return "" if content.nil? || content.empty?

        # Handle different content formats
        first_item = content.first
        case first_item
        when Hash
          case first_item[:type]
          when "text"
            first_item[:text]
          when "image"
            # Return a structured response for images
            {
              type: "image",
              data: first_item[:data],
              mime_type: first_item[:mimeType] || "image/png"
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
        @closed = true
        @sse_thread&.kill
        @connection&.close
      end

      def unique_key
        parametrized_url = @url.parameterize.underscore.gsub("https_", "")
        Digest::SHA256.hexdigest(parametrized_url)[0..2]
      end

      private

      # Establishes and maintains the SSE connection
      def establish_sse_connection
        @sse_thread = Thread.new do
          headers = {
            "Accept" => "text/event-stream",
            "Cache-Control" => "no-cache",
            "Connection" => "keep-alive",
            "MCP-Version" => PROTOCOL_VERSION
          }.merge(@headers)

          @connection = Faraday.new(url: @url) do |faraday|
            faraday.options.timeout = CONNECTION_TIMEOUT
            faraday.options.open_timeout = OPEN_TIMEOUT
          end

          @connection.get do |req|
            req.headers = headers
            req.options.on_data = proc do |chunk, _size|
              next if @closed

              @buffer << chunk
              process_sse_buffer
            end
          end
        rescue StandardError => e
          # puts "[MCP DEBUG] SSE connection error: #{e.message}"
          @event_queue << { error: e }
        end

        # Wait for endpoint discovery
        loop do
          event = @event_queue.pop
          if event[:error]
            raise ProtocolError, "SSE connection failed: #{event[:error].message}"
          elsif event[:endpoint_url]
            @endpoint_url = event[:endpoint_url]
            break
          end
        end

        # Initialize the MCP session
        initialize_mcp_session
      end

      # Process SSE buffer for complete events
      def process_sse_buffer
        while (idx = @buffer.index("\n\n"))
          event_text = @buffer.slice!(0..idx + 1)
          event_type, event_data = parse_sse_fields(event_text)

          case event_type
          when "endpoint"
            endpoint_url = build_absolute_url(@url, event_data)
            @event_queue << { endpoint_url: }
          when "message"
            handle_message_event(event_data)
          end
        end
      end

      # Handle SSE message events
      def handle_message_event(event_data)
        parsed = JSON.parse(event_data, symbolize_names: true)

        # Handle different message types
        case parsed
        when ->(p) { p[:method] == "initialize" && p.dig(:params, :endpoint_url) }
          # Legacy endpoint discovery
          endpoint_url = parsed.dig(:params, :endpoint_url)
          @event_queue << { endpoint_url: }
        when ->(p) { p[:id] && p[:result] }
          @event_queue << { id: parsed[:id], result: parsed[:result] }
        when ->(p) { p[:result] }
          @event_queue << { result: parsed[:result] }
        end
      rescue JSON::ParserError => e
        puts "[MCP DEBUG] Error parsing message: #{e.message}"
        puts "[MCP DEBUG] Message data: #{event_data}"
      end

      # Initialize the MCP session
      def initialize_mcp_session
        request_id = SecureRandom.uuid
        send_json_rpc(request_id, "initialize", {
                        protocolVersion: PROTOCOL_VERSION,
                        capabilities: {
                          roots: { listChanged: true },
                          sampling: {}
                        },
                        clientInfo: {
                          name: "Raix",
                          version: Raix::VERSION
                        }
                      })

        # Wait for initialization response
        response = wait_for_response(request_id)

        # Send acknowledgment if needed
        return unless response.dig(:capabilities, :tools, :listChanged)

        send_notification("notifications/initialized", {})
      end

      # Send a JSON-RPC request
      def send_json_rpc(id, method, params)
        body = {
          jsonrpc: JSONRPC_VERSION,
          id:,
          method:,
          params:
        }

        # Use a new connection for the POST request
        conn = Faraday.new(url: @endpoint_url) do |faraday|
          faraday.options.timeout = CONNECTION_TIMEOUT
        end

        conn.post do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = body.to_json
        end
      rescue StandardError => e
        raise ProtocolError, "Failed to send request: #{e.message}"
      end

      # Send a notification (no response expected)
      def send_notification(method, params)
        body = {
          jsonrpc: JSONRPC_VERSION,
          method:,
          params:
        }

        conn = Faraday.new(url: @endpoint_url) do |faraday|
          faraday.options.timeout = CONNECTION_TIMEOUT
        end

        conn.post do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = body.to_json
        end
      rescue StandardError => e
        puts "[MCP DEBUG] Error sending notification: #{e.message}"
      end

      # Wait for a response with a specific ID
      def wait_for_response(request_id)
        timeout = Time.now + CONNECTION_TIMEOUT

        loop do
          if Time.now > timeout
            raise ProtocolError, "Timeout waiting for response"
          end

          # Use non-blocking pop with timeout
          begin
            event = @event_queue.pop(true) # non_block = true
          rescue ThreadError
            # Queue is empty, wait a bit
            sleep 0.1
            next
          end

          if event[:error]
            raise ProtocolError, "SSE error: #{event[:error].message}"
          elsif event[:id] == request_id && event[:result]
            return event[:result]
          elsif event[:result] && !event[:id]
            return event[:result]
          else
            @event_queue << event
            sleep 0.01
          end
        end
      end

      # Parses SSE event fields from raw text.
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

      # Builds an absolute URL for candidate relative to base.
      def build_absolute_url(base, candidate)
        uri = URI.parse(candidate)
        return candidate if uri.absolute?

        URI.join(base, candidate).to_s
      rescue URI::InvalidURIError
        candidate
      end
    end
  end
end
