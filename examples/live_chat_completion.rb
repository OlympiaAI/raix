#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv"
require "time"
require "raix"

# Load environment variables from .env file
Dotenv.load

# Configure Raix with API keys
Raix.configure do |config|
  config.openrouter_api_key = ENV.fetch("OR_ACCESS_TOKEN", nil)
  config.openai_api_key = ENV.fetch("OAI_ACCESS_TOKEN", nil)
end

module Examples
  class LiveChatCompletion
    include Raix::ChatCompletion
    include Raix::FunctionDispatch

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "meta-llama/llama-3.3-8b-instruct:free")
      config.temperature = 0.2
    end

    function :current_time, "Return the current UTC time", format: { type: "string" } do |_arguments|
      Time.now.utc.iso8601
    end

    def self.run!(prompt: nil, enable_tools: true, **chat_params)
      new(prompt:, enable_tools:, **chat_params).run!
    end

    def initialize(prompt: nil, enable_tools: true, **chat_params)
      ENV["RAIX_EXAMPLE_PROMPT"]&.strip => env_prompt if ENV["RAIX_EXAMPLE_PROMPT"]
      prompt ||= env_prompt || default_prompt

      transcript << { system: system_instructions }
      transcript << { user: prompt }

      @enable_tools = enable_tools
      @chat_params = build_chat_params(chat_params)
    end

    def run!
      chat_completion(
        params: @chat_params,
        available_tools: @enable_tools ? nil : false
      )
    end

    private

    def system_instructions
      <<~SYSTEM.squish
        You are a production readiness check. Confirm that Raix can reach the configured
        model and produce a succinct answer. Use the current_time tool when relevant.
      SYSTEM
    end

    def default_prompt
      <<~PROMPT.squish
        Explain in one or two sentences how I can confirm Raix is wired up correctly.
      PROMPT
    end

    def build_chat_params(overrides)
      overrides.compact => params

      params[:max_tokens] ||= configuration.max_tokens
      params[:temperature] ||= configuration.temperature

      params
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts Examples::LiveChatCompletion.run!
end
