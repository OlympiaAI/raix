#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv"
require "io/console"
require "raix"

# Load environment variables from .env file
Dotenv.load

# Configure Raix with API keys
Raix.configure do |config|
  config.openrouter_api_key = ENV.fetch("OR_ACCESS_TOKEN", nil)
  config.openai_api_key = ENV.fetch("OAI_ACCESS_TOKEN", nil)
end

module Examples
  # Demonstrates real-time streaming of AI responses token-by-token.
  # Perfect for building responsive chat interfaces and showing progress.
  class StreamingChat
    include Raix::ChatCompletion

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.7
    end

    attr_reader :response_text

    def initialize
      @response_text = ""
    end

    # Example 1: Simple streaming with character-by-character output
    def simple_stream(prompt)
      puts "💬 Prompt: #{prompt}"
      puts "🤖 Response (streaming):"
      puts

      @response_text = ""

      # Set the stream handler
      self.stream = lambda do |chunk|
        @response_text += chunk
        print chunk
        $stdout.flush
      end

      transcript << { user: prompt }
      chat_completion

      puts "\n"
    end

    # Example 2: Streaming with progress indicator
    def stream_with_progress(prompt)
      puts "💬 Prompt: #{prompt}"
      print "🤖 Thinking"

      @response_text = ""
      started = false

      self.stream = lambda do |chunk|
        unless started
          # Clear the "Thinking..." line
          print "\r#{" " * 20}\r"
          puts "🤖 Response:"
          puts
          started = true
        end

        @response_text += chunk
        print chunk
        $stdout.flush
      end

      # Show thinking dots while waiting
      thread = Thread.new do
        sleep 0.5
        3.times do
          print "."
          $stdout.flush
          sleep 0.3
        end
      end

      transcript << { user: prompt }
      chat_completion

      thread.kill
      puts "\n"
    end

    # Example 3: Streaming with word count and timing
    def stream_with_metrics(prompt)
      puts "💬 Prompt: #{prompt}"
      puts "🤖 Response (with metrics):"
      puts

      @response_text = ""
      start_time = Time.now
      token_count = 0

      self.stream = lambda do |chunk|
        @response_text += chunk
        token_count += 1
        print chunk
        $stdout.flush
      end

      transcript << { user: prompt }
      chat_completion

      end_time = Time.now
      duration = (end_time - start_time).round(2)
      word_count = @response_text.split.length
      tokens_per_second = (token_count / duration).round(1)

      puts "\n"
      puts "-" * 60
      puts "📊 Metrics:"
      puts "   Words: #{word_count} | Tokens: #{token_count} | Time: #{duration}s | Speed: #{tokens_per_second} tok/s"
      puts
    end

    # Example 4: Interactive streaming chat
    def interactive_chat
      puts "🎮 Interactive Streaming Chat"
      puts "=" * 60
      puts "Type your messages below. Type 'exit' to quit."
      puts "=" * 60
      puts

      loop do
        print "You: "
        user_input = $stdin.gets&.chomp
        break if user_input.nil? || user_input.downcase == "exit"

        next if user_input.strip.empty?

        print "AI:  "
        @response_text = ""

        self.stream = lambda do |chunk|
          @response_text += chunk
          print chunk
          $stdout.flush
        end

        transcript << { user: user_input }
        chat_completion

        # Save the AI's response to transcript
        # (streaming mode doesn't auto-save)
        transcript << { assistant: @response_text }

        puts "\n"
      end

      puts "\n👋 Chat ended. Goodbye!"
    end

    def self.run!
      chat = new

      puts "🌊 Raix Streaming Chat Demo"
      puts "Real-time token-by-token response generation"
      puts "=" * 60
      puts

      # Example 1: Simple streaming
      puts "Example 1: Basic Streaming"
      puts "-" * 60
      chat.simple_stream("Write a haiku about Ruby programming")
      puts

      sleep 1

      # Example 2: Streaming with progress indicator
      puts "Example 2: Streaming with Progress Indicator"
      puts "-" * 60
      chat.stream_with_progress("Explain what makes a good software engineer in 2-3 sentences")
      puts

      sleep 1

      # Example 3: Streaming with metrics
      puts "Example 3: Streaming with Performance Metrics"
      puts "-" * 60
      chat.stream_with_metrics("List 5 benefits of using Ruby on Rails")
      puts

      # Example 4: Interactive chat (optional)
      if ARGV.include?("--interactive")
        sleep 1
        puts "\n#{"=" * 60}\n"
        chat.interactive_chat
      else
        puts "\n#{"=" * 60}"
        puts "✨ Streaming demo complete!"
        puts "\nTip: Run with --interactive flag for an interactive chat session:"
        puts "     bundle exec ruby examples/streaming_chat.rb --interactive"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Examples::StreamingChat.run!
end
