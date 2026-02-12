# frozen_string_literal: true

RSpec.describe Raix::Configuration do
  describe "#client?" do
    context "with native OpenRouter API key" do
      it "returns true" do
        configuration = described_class.new(fallback: nil)
        configuration.openrouter_api_key = "test_key"
        expect(configuration.client?).to eq true
      end
    end

    context "with native OpenAI API key" do
      it "returns true" do
        configuration = described_class.new(fallback: nil)
        configuration.openai_api_key = "test_key"
        expect(configuration.client?).to eq true
      end
    end

    context "with legacy RubyLLM config shim" do
      it "returns true when keys are present" do
        configuration = described_class.new(fallback: nil)
        legacy_config = Struct.new(:openai_api_key, :openrouter_api_key, :anthropic_api_key, :gemini_api_key).new(nil, "test_key", nil, nil)
        configuration.ruby_llm_config = legacy_config
        expect(configuration.client?).to eq true
      end
    end

    context "without any API configuration" do
      it "returns false" do
        configuration = described_class.new(fallback: nil)
        configuration.openai_api_key = nil
        configuration.openrouter_api_key = nil
        expect(configuration.client?).to eq false
      end
    end
  end
end
