# frozen_string_literal: true

module Raix
  # Adapter to convert between Raix's transcript array format and RubyLLM's Message objects
  class TranscriptAdapter
    attr_reader :ruby_llm_chat

    def initialize(ruby_llm_chat)
      @ruby_llm_chat = ruby_llm_chat
      @pending_messages = []
    end

    # Add a message in Raix format (hash) to the transcript
    def <<(message_hash)
      case message_hash
      when Array
        # Handle nested arrays (from function dispatch)
        message_hash.each { |msg| self << msg }
      when Hash
        add_message_from_hash(message_hash)
      end
      self
    end

    # Return all messages in Raix-compatible format
    def flatten
      ruby_llm_messages = @ruby_llm_chat.messages.map { |msg| message_to_raix_format(msg) }
      pending = @pending_messages.map { |msg| normalize_message_format(msg) }
      (ruby_llm_messages + pending).flatten
    end

    # Get all messages including pending ones
    def to_a
      flatten
    end

    # Allow iteration
    def compact
      flatten.compact
    end

    # Clear all messages
    def clear
      @ruby_llm_chat.messages = []
      @pending_messages.clear
      self
    end

    # Get last message
    def last
      flatten.last
    end

    # Get size of transcript
    def size
      flatten.size
    end

    alias length size

    private

    def add_message_from_hash(hash)
      # Raix abbreviated format: { system: "text" }, { user: "text" }, { assistant: "text" }
      if hash.key?(:system) || hash.key?("system")
        # Pending only, like every other role. Writing it into the memoized
        # chat as well sent each system prompt twice and rejected structured
        # (array) content before ChatCompletion could translate it.
        content = hash[:system] || hash["system"]
        @pending_messages << { role: "system", content: }
      elsif hash.key?(:user) || hash.key?("user")
        content = hash[:user] || hash["user"]
        # Don't add to ruby_llm_chat yet - wait for chat_completion call
        @pending_messages << { role: "user", content: }
      elsif hash.key?(:assistant) || hash.key?("assistant")
        content = hash[:assistant] || hash["assistant"]
        @pending_messages << { role: "assistant", content: }
      elsif hash[:role] || hash["role"]
        # Standard OpenAI format (tool messages, assistant with tool_calls, etc.)
        @pending_messages << hash.with_indifferent_access
      end
    end

    def message_to_raix_format(message)
      # Return in Raix abbreviated format { system: "...", user: "...", assistant: "..." }
      # unless it's a tool message which needs full format
      if message.tool_call? || message.tool_result?
        result = {
          role: message.role.to_s,
          content: message.content
        }
        result[:tool_calls] = message.tool_calls if message.tool_call?
        result[:tool_call_id] = message.tool_call_id if message.tool_result?
        result
      else
        # Use abbreviated format
        { message.role.to_sym => message.content }
      end
    end

    def normalize_message_format(msg)
      # If already in abbreviated format, return as-is
      return msg if msg.key?(:system) || msg.key?(:user) || msg.key?(:assistant)
      return msg if msg["system"] || msg["user"] || msg["assistant"]

      # If in standard format with role/content, convert to abbreviated
      if msg[:role] || msg["role"]
        role = (msg[:role] || msg["role"]).to_sym
        content = msg[:content] || msg["content"]

        # Tool messages stay in full format
        if msg[:tool_calls] || msg["tool_calls"] || msg[:tool_call_id] || msg["tool_call_id"]
          return msg
        end

        # Convert to abbreviated format
        { role => content }
      else
        msg
      end
    end
  end
end
