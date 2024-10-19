# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::MessageAdapters::Base do
  let(:context) { double("Context", model: "anthropic/claude-3", cache_at: 10) }
  let(:adapter) { described_class.new(context) }

  describe "#transform" do
    it "returns the message if it already has a role" do
      message = { role: "user", content: "Hello" }
      expect(adapter.transform(message)).to eq(message)
    end

    it "transforms a function call message" do
      message = { function: { name: "my_function", arguments: { param: "value" } } }
      expected = { role: "assistant", name: "my_function", content: { param: "value" }.to_json }
      expect(adapter.transform(message)).to eq(expected)
    end

    it "transforms a result message" do
      message = { result: "Hello", name: "my_function" }
      expected = { role: "function", name: "my_function", content: "Hello" }
      expect(adapter.transform(message)).to eq(expected)
    end

    it "transforms a message with a single key-value pair" do
      message = { user: "Hello" }
      expected = { role: "user", content: "Hello" }
      expect(adapter.transform(message)).to eq(expected)
    end

    it "transforms a message with a large content" do
      message = { user: "Hello" * 5 }
      expected = { role: "user", content: [{ type: "text", text: "Hello" * 5, cache_control: { type: "ephemeral" } }] }
      expect(adapter.transform(message)).to eq(expected)
    end
  end
end
