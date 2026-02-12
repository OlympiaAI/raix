# frozen_string_literal: true

require "faraday"
require "faraday/retry"

module Raix
  module Runtime
    # HTTP transport wrapper with retries, timeout handling, and stream parsing.
    class Transport
      DEFAULT_TIMEOUT = 120
      DEFAULT_OPEN_TIMEOUT = 30
      DEFAULT_RETRIES = 2

      def initialize(timeout: DEFAULT_TIMEOUT, open_timeout: DEFAULT_OPEN_TIMEOUT, retries: DEFAULT_RETRIES)
        @timeout = timeout
        @open_timeout = open_timeout
        @retries = retries
      end

      def post_json(url:, headers:, payload:, provider:)
        response = connection.post(url) do |req|
          req.options.timeout = @timeout
          req.options.open_timeout = @open_timeout
          req.headers.update(default_headers.merge(headers))
          req.body = JSON.generate(payload)
        end

        parse_json_response(response, provider:)
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise TransportError.new("#{provider} request failed: #{e.message}", provider:)
      end

      def post_stream(url:, headers:, payload:, provider:)
        parser = StreamParser.new
        accumulator = StreamAccumulator.new

        connection.post(url) do |req|
          req.options.timeout = @timeout
          req.options.open_timeout = @open_timeout
          req.headers.update(default_headers.merge(headers).merge("Accept" => "text/event-stream"))
          req.body = JSON.generate(payload.merge(stream: true))
          req.options.on_data = lambda do |chunk, _overall_received_bytes, _env|
            parser.feed(chunk).each do |event|
              next if event == "[DONE]"

              parsed = JSON.parse(event)
              accumulator.consume(parsed)

              delta_content = parsed.dig("choices", 0, "delta", "content")
              yield delta_content if delta_content && block_given?
            rescue JSON::ParserError
              next
            end
          end
        end

        accumulator.envelope
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise TransportError.new("#{provider} stream request failed: #{e.message}", provider:)
      end

      private

      def connection
        @connection ||= Faraday.new do |f|
          f.request :retry,
                    max: @retries,
                    interval: 0.2,
                    interval_randomness: 0.5,
                    backoff_factor: 2,
                    methods: %i[get post]
          f.adapter Faraday.default_adapter
        end
      end

      def default_headers
        { "Content-Type" => "application/json" }
      end

      def parse_json_response(response, provider:)
        body = response.body.to_s
        parsed = body.empty? ? {} : JSON.parse(body)

        if response.status.to_i >= 400
          error_message = parsed.dig("error", "message") || parsed["message"] || "HTTP #{response.status}"
          raise TransportError.new(
            "#{provider} request failed (#{response.status}): #{error_message}",
            status: response.status,
            provider:,
            body: parsed
          )
        end

        parsed
      rescue JSON::ParserError
        raise TransportError.new("#{provider} request returned non-JSON response", status: response.status, provider:, body:)
      end
    end
  end
end
