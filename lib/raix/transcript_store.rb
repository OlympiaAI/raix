# frozen_string_literal: true

require "thread"

module Raix
  # Thread-safe transcript store used by ChatCompletion.
  # Stores messages in abbreviated format when possible while preserving tool payloads.
  class TranscriptStore
    def initialize
      @entries = []
      @mutex = Mutex.new
    end

    def <<(message)
      @mutex.synchronize do
        @entries << normalize_entry(message)
      end
      self
    end

    def flatten
      snapshot = @mutex.synchronize { @entries.dup }
      snapshot.flatten.compact.map { |entry| normalize_output(entry) }
    end

    def to_a
      flatten
    end

    def compact
      flatten.compact
    end

    def clear
      @mutex.synchronize { @entries.clear }
      self
    end

    def last
      flatten.last
    end

    def size
      @mutex.synchronize { @entries.flatten.compact.size }
    end

    alias length size

    private

    def normalize_entry(entry)
      case entry
      when Array
        entry.map { |message| normalize_entry(message) }
      when Hash
        normalize_message(entry)
      else
        entry
      end
    end

    def normalize_message(message)
      hash = message.transform_keys(&:to_sym)

      if hash.key?(:role)
        role = hash[:role].to_s
        content = hash[:content]
        tool_payload = hash.key?(:tool_calls) || hash.key?(:tool_call_id) || hash.key?(:name)

        if %w[system user assistant].include?(role) && !tool_payload
          { role.to_sym => content }
        else
          hash
        end
      else
        hash
      end
    end

    def normalize_output(entry)
      return entry unless entry.is_a?(Hash)

      hash = entry.transform_keys(&:to_sym)
      return hash if hash.key?(:system) || hash.key?(:user) || hash.key?(:assistant)

      role = hash[:role]&.to_s
      tool_payload = hash.key?(:tool_calls) || hash.key?(:tool_call_id) || hash.key?(:name)
      return hash unless %w[system user assistant].include?(role) && !tool_payload

      { role.to_sym => hash[:content] }
    end
  end
end
