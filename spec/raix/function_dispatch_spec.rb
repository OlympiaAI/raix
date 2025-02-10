# frozen_string_literal: true

class WhatIsTheWeather
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :check_weather, "Check the weather for a location", location: { type: "string" } do |arguments|
    "The weather in #{arguments[:location]} is hot and sunny"
  end

  # non_exposed_method is not exporsed as a tool function and should not be callable through the chat completion API
  def non_exposed_method(...)
    raise "This should NEVER be called by the chat completion API"
  end

  def initialize
    self.seed = 9999
    transcript << { user: "What is the weather in Zipolite, Oaxaca?" }
  end
end

class MultipleToolCalls
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :call_this_function_twice do |arguments|
    @callback.call(arguments)
  end

  def initialize(callback)
    @callback = callback
  end
end

RSpec.describe Raix::FunctionDispatch, :vcr do
  let(:callback) { double("callback") }

  it "can call a function and loop to provide text response" do
    response = WhatIsTheWeather.new.chat_completion(openai: "gpt-4o", loop: true)
    expect(response.first).to include("hot and sunny")
  end

  it "supports multiple tool calls in a single response" do
    subject = MultipleToolCalls.new(callback)
    subject.transcript << { user: "For testing purposes, call the provided tool function twice in a single response." }
    expect(callback).to receive(:call).twice
    subject.chat_completion(openai: "gpt-4o")
  end

  # This simulates a middleman on the network that rewrites the function name to anything else
  def decorate_clients_with_fake_middleman!
    result = { openai: Raix.configuration.openai_client, openrouter: Raix.configuration.openrouter_client }
    mocked_middleman =
      Class.new(SimpleDelegator) do
        def chat(...)
          __getobj__.chat(...).tap do |result|
            result.dig("choices", 0, "message", "tool_calls")&.each do |tool_call|
              tool_call["function"]["name"] = "non_exposed_method"
            end
          end
        end

        def complete(...)
          __getobj__.complete(...).tap do |result|
            result.dig("choices", 0, "message", "tool_calls")&.each do |tool_call|
              tool_call["function"]["name"] = "non_exposed_method"
            end
          end
        end
      end
    Raix.configuration.openai_client = mocked_middleman.new(Raix.configuration.openai_client)
    Raix.configuration.openrouter_client = mocked_middleman.new(Raix.configuration.openrouter_client)
    result
  end

  # Since we are using the send method to execute tools calls, we have to make sure
  # that the method was explicitely defined as a tool function.
  #
  # Otherwise, a middleman on the network could rewrite the method name to anything else and execute
  # arbitrary code from the class.
  it "does not allow non exposed methods to be called" do
    previous_clients = decorate_clients_with_fake_middleman!
    begin
      # With OpenAI:
      expect { WhatIsTheWeather.new.chat_completion(openai: "gpt-4o", loop: true) }.to raise_error(/unauthorized function call/i)
      # With OpenRouter:
      expect { WhatIsTheWeather.new.chat_completion(openai: false, params: { model: "gpt-4o" }, loop: true) }.to raise_error(/unauthorized function call/i)
    ensure
      Raix.configuration.openai_client = previous_clients[:openai]
      Raix.configuration.openrouter_client = previous_clients[:openrouter]
    end
  end
end
