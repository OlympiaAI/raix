# frozen_string_literal: true

# Regression coverage: Raix must not inject a default `temperature` into the
# request when the caller hasn't set one.
#
# Some OpenRouter-routed providers (notably Anthropic's Claude 4.7 family) do
# not list `temperature` in their `supported_parameters`. When `json: true`
# adds `provider.require_parameters: true` to the payload, an unsolicited
# `temperature: 0.0` from a Raix default causes OpenRouter to return
# "No endpoints found that can handle the requested parameters" (404).
class TemperatureDefaultProbe
  include Raix::ChatCompletion
end

RSpec.describe Raix::ChatCompletion, "default temperature handling" do
  let(:instance) { TemperatureDefaultProbe.new }

  let(:fake_response_message) do
    instance_double(
      "RubyLLM::Message",
      content: "ok",
      tool_calls: nil,
      tool_call?: false,
      input_tokens: 1,
      output_tokens: 1,
      model_id: "anthropic/claude-opus-4-7",
      raw: nil
    )
  end

  let(:fake_chat) do
    instance_double(
      "RubyLLM::Chat",
      with_instructions: nil,
      add_message: nil,
      with_temperature: nil,
      with_params: nil,
      with_tool: nil,
      ask: fake_response_message,
      complete: fake_response_message
    )
  end

  before { allow(RubyLLM).to receive(:chat).and_return(fake_chat) }

  it "does not call with_temperature when no temperature is set anywhere" do
    instance.send(:ruby_llm_request,
                  params: {},
                  model: "anthropic/claude-opus-4-7",
                  messages: [{ role: "user", content: "hi" }])

    expect(fake_chat).not_to have_received(:with_temperature)
  end

  it "does not include temperature in additional params when unset" do
    instance.send(:ruby_llm_request,
                  params: {},
                  model: "anthropic/claude-opus-4-7",
                  messages: [{ role: "user", content: "hi" }])

    expect(fake_chat).not_to have_received(:with_params) { |kwargs|
      kwargs.key?(:temperature)
    }
  end

  it "still forwards an explicitly-set temperature (including 0.0)" do
    instance.temperature = 0.0
    instance.chat_completion(messages: [{ user: "hi" }])

    expect(fake_chat).to have_received(:with_temperature).with(0.0)
  end

  it "forwards a class-level configured temperature" do
    klass = Class.new do
      include Raix::ChatCompletion
      configure { |config| config.temperature = 0.3 }
    end
    klass.new.chat_completion(messages: [{ user: "hi" }])

    expect(fake_chat).to have_received(:with_temperature).with(0.3)
  end
end

RSpec.describe Raix::Configuration, "temperature default" do
  it "leaves temperature unset on a fresh configuration" do
    expect(described_class.new.temperature).to be_nil
  end

  it "still defaults max_tokens, max_completion_tokens, and model" do
    config = described_class.new

    expect(config.max_tokens).to eq(Raix::Configuration::DEFAULT_MAX_TOKENS)
    expect(config.max_completion_tokens).to eq(Raix::Configuration::DEFAULT_MAX_COMPLETION_TOKENS)
    expect(config.model).to eq(Raix::Configuration::DEFAULT_MODEL)
  end
end
