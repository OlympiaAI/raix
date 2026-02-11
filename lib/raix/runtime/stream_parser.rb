# frozen_string_literal: true

module Raix
  module Runtime
    # Minimal SSE parser for OpenAI-compatible stream events.
    class StreamParser
      def initialize
        @buffer = +""
      end

      def feed(chunk)
        @buffer << chunk.to_s
        events = []

        while (delimiter_index = event_delimiter_index)
          raw_event = @buffer.slice!(0, delimiter_index + delimiter_size)
          events.concat(parse_event(raw_event))
        end

        events
      end

      private

      def event_delimiter_index
        @buffer.index("\r\n\r\n") || @buffer.index("\n\n")
      end

      def delimiter_size
        @buffer.include?("\r\n\r\n") ? 4 : 2
      end

      def parse_event(raw_event)
        raw_event.each_line.filter_map do |line|
          stripped = line.strip
          next unless stripped.start_with?("data:")

          value = stripped.sub(/\Adata:\s?/, "")
          next if value.empty?

          value
        end
      end
    end
  end
end
