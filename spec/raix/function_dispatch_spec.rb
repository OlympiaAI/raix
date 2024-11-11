# frozen_string_literal: true

class WhatIsTheWeather
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :check_weather, "Check the weather for a location", location: { type: "string" } do |arguments|
    "The weather in #{arguments[:location]} is hot and sunny"
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
end
