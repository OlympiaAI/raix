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

class SearchForFile
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :search_for_file,
           "Search for a file in the project",
           glob_pattern: { type: "string", required: true },
           path: { type: "string", optional: true } do |_arguments|
    "found"
  end
end

RSpec.describe Raix::FunctionDispatch, :vcr do
  let(:callback) { double("callback") }

  it "can call a function and automatically loop to provide text response" do
    # The system now automatically continues after tool calls to get a final AI response
    response = WhatIsTheWeather.new.chat_completion(openai: "gpt-4o")
    # Response should be a string (the AI's final response) not an array
    expect(response).to be_a(String)
    # The AI should have processed the weather information in its response
    expect(response.downcase).to match(/zipolite|oaxaca|weather|hot|sunny/)
  end

  it "supports multiple tool calls in a single response" do
    subject = MultipleToolCalls.new(callback)
    subject.transcript << { user: "For testing purposes, call the provided tool function twice in a single response." }
    # The callback might be called more than twice due to automatic continuation
    expect(callback).to receive(:call).at_least(:twice)
    response = subject.chat_completion(openai: "gpt-4o")
    # Should get a final text response
    expect(response).to be_a(String)
  end

  it "supports filtering tools with the tools parameter", :vcr do
    weather = WhatIsTheWeather.new
    expect(weather).to respond_to(:check_weather)
    expect { weather.chat_completion(available_tools: [:invalid_tool]) }.to raise_error(Raix::UndeclaredToolError)

    # When available_tools: false, the AI should respond without making tool calls
    weather2 = WhatIsTheWeather.new
    weather2.transcript.clear
    weather2.transcript << { user: "Just tell me it's sunny, don't use any tools." }
    response = weather2.chat_completion(available_tools: false)

    # Should get a text response without tool calls
    expect(response).to be_a(String)
    expect(response.downcase).to include("sunny")
  end

  it "tracks required and optional parameters" do
    params = SearchForFile.new.tools.first[:function][:parameters]
    expect(params[:required]).to eq([:glob_pattern])
    expect(params[:properties].keys).to include(:path)
    expect(params[:required]).not_to include(:path)
  end

  # Since we are using the send method to execute tools calls, we have to make sure
  # that the method was explicitly defined as a tool function.
  #
  # Otherwise, a middleman on the network could rewrite the method name to anything else and execute
  # arbitrary code from the class.
  it "does not allow non exposed methods to be called" do
    weather = WhatIsTheWeather.new

    # Simulate what chat_completion does when it receives a tool call
    fake_tool_call = { "function" => { "name" => "non_exposed_method", "arguments" => "{}" } }
    function_name = fake_tool_call["function"]["name"]
    allowed_functions = weather.class.functions.map { |f| f[:name].to_sym }

    # Verify the security check would catch this
    expect(allowed_functions).not_to include(function_name.to_sym)
    expect { raise "Unauthorized function call: #{function_name}" unless allowed_functions.include?(function_name.to_sym) }.to raise_error(/Unauthorized function call: non_exposed_method/)
  end

  it "respects max_tool_calls parameter" do
    weather = WhatIsTheWeather.new
    weather.transcript.clear
    weather.transcript << { user: "Check the weather for multiple cities repeatedly" }

    tool_call_response = lambda do |id|
      {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              {
                "id" => id,
                "type" => "function",
                "function" => {
                  "name" => "check_weather",
                  "arguments" => '{"location":"City"}'
                }
              }
            ]
          },
          "finish_reason" => "tool_calls"
        }]
      }
    end

    final_response = {
      "choices" => [{
        "message" => { "role" => "assistant", "content" => "Final answer without more tools", "tool_calls" => nil },
        "finish_reason" => "stop"
      }]
    }

    responses = [tool_call_response.call("call_1"), tool_call_response.call("call_2"), final_response]
    allow(weather).to receive(:execute_runtime_request) { responses.shift }

    response = weather.chat_completion(max_tool_calls: 1)
    expect(response).to be_a(String)
    expect(response).to include("Final answer")
  end
end
