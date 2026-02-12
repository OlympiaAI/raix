# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::Runtime::StreamAccumulator do
  subject(:accumulator) { described_class.new }

  it "accumulates assistant content chunks" do
    accumulator.consume({ "choices" => [{ "delta" => { "content" => "Hello " }, "finish_reason" => nil }] })
    accumulator.consume({ "choices" => [{ "delta" => { "content" => "world" }, "finish_reason" => "stop" }] })

    envelope = accumulator.envelope
    expect(envelope.dig("choices", 0, "message", "content")).to eq("Hello world")
    expect(envelope.dig("choices", 0, "finish_reason")).to eq("stop")
  end

  it "accumulates fragmented tool call deltas" do
    accumulator.consume(
      {
        "choices" => [
          {
            "delta" => {
              "tool_calls" => [
                {
                  "index" => 0,
                  "id" => "call_123",
                  "type" => "function",
                  "function" => { "name" => "check_", "arguments" => "{\"loc" }
                }
              ]
            },
            "finish_reason" => nil
          }
        ]
      }
    )

    accumulator.consume(
      {
        "choices" => [
          {
            "delta" => {
              "tool_calls" => [
                {
                  "index" => 0,
                  "function" => { "name" => "weather", "arguments" => "ation\":\"Paris\"}" }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }
    )

    envelope = accumulator.envelope
    tool_call = envelope.dig("choices", 0, "message", "tool_calls", 0)
    expect(tool_call["id"]).to eq("call_123")
    expect(tool_call.dig("function", "name")).to eq("check_weather")
    expect(tool_call.dig("function", "arguments")).to eq("{\"location\":\"Paris\"}")
    expect(envelope.dig("choices", 0, "finish_reason")).to eq("tool_calls")
  end
end
