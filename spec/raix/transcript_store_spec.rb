# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::TranscriptStore do
  subject(:store) { described_class.new }

  it "stores abbreviated messages as-is" do
    store << { user: "Hello" }
    expect(store.flatten).to eq([{ user: "Hello" }])
  end

  it "normalizes standard role/content format into abbreviated format when possible" do
    store << { role: "assistant", content: "Hi there" }
    expect(store.flatten).to eq([{ assistant: "Hi there" }])
  end

  it "preserves tool payload messages in full format" do
    store << { role: "tool", tool_call_id: "call_1", name: "check_weather", content: "Sunny" }

    expect(store.flatten).to eq([
                                  { role: "tool", tool_call_id: "call_1", name: "check_weather", content: "Sunny" }
                                ])
  end

  it "supports atomic array appends and flattening" do
    store << [{ user: "A" }, { assistant: "B" }]
    expect(store.flatten).to eq([{ user: "A" }, { assistant: "B" }])
    expect(store.size).to eq(2)
  end

  it "clears the transcript" do
    store << { user: "Hello" }
    store.clear
    expect(store.flatten).to eq([])
  end

  it "is safe for concurrent appends" do
    threads = 10.times.map do |i|
      Thread.new do
        50.times { |j| store << { user: "t#{i}-#{j}" } }
      end
    end
    threads.each(&:join)

    expect(store.size).to eq(500)
  end
end
