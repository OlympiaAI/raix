# frozen_string_literal: true

require "spec_helper"

class TestCallablePrompt
  include Raix::ChatCompletion

  def initialize(context)
    @context = context
  end

  def call(input = nil)
    "Called with: #{input}"
  end
end

class TestPromptDeclarations
  include Raix::ChatCompletion
  include Raix::PromptDeclarations

  prompt call: TestCallablePrompt
end

class TestTextPromptDeclarations
  include Raix::ChatCompletion
  include Raix::PromptDeclarations

  prompt text: "Hello, world!"
end

class TestMixedPromptDeclarations
  include Raix::ChatCompletion
  include Raix::PromptDeclarations

  prompt call: TestCallablePrompt
  prompt text: -> { "Dynamic text" }
end

RSpec.describe "PromptDeclarations" do
  describe "prompt declarations" do
    it "supports call syntax without text" do
      expect(TestPromptDeclarations.prompts.count).to eq(1)
      expect(TestPromptDeclarations.prompts.first.call).to eq(TestCallablePrompt)
      expect(TestPromptDeclarations.prompts.first.text).to be_nil
    end

    it "supports text syntax without call" do
      expect(TestTextPromptDeclarations.prompts.count).to eq(1)
      expect(TestTextPromptDeclarations.prompts.first.call).to be_nil
      expect(TestTextPromptDeclarations.prompts.first.text).to eq("Hello, world!")
    end

    it "supports mixing call and text prompts" do
      expect(TestMixedPromptDeclarations.prompts.count).to eq(2)
      expect(TestMixedPromptDeclarations.prompts.first.call).to eq(TestCallablePrompt)
      expect(TestMixedPromptDeclarations.prompts.last.text).to be_a(Proc)
    end
  end

  describe "chat_completion execution" do
    it "executes callable prompts without text" do
      instance = TestPromptDeclarations.new
      allow(instance).to receive(:transcript).and_return([])

      # The callable should be instantiated and called
      result = instance.chat_completion
      expect(result).to eq("Called with: ")
    end
  end
end
