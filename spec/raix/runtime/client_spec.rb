# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::Runtime::Client do
  let(:configuration) { Raix::Configuration.new(fallback: nil) }
  subject(:client) { described_class.new(configuration:) }

  before do
    configuration.openai_api_key = "openai-key"
    configuration.openrouter_api_key = "openrouter-key"
  end

  it "routes gpt-* models to OpenAI" do
    openai_provider = instance_double(Raix::Runtime::Providers::OpenAI)
    allow(Raix::Runtime::Providers::OpenAI).to receive(:new).and_return(openai_provider)
    allow(openai_provider).to receive(:chat_completions).and_return({ "choices" => [] })

    client.complete(model: "gpt-4o", messages: [], params: {}, stream: nil, openai_override: nil)

    expect(openai_provider).to have_received(:chat_completions)
  end

  it "routes non-openai models to OpenRouter" do
    openrouter_provider = instance_double(Raix::Runtime::Providers::OpenRouter)
    allow(Raix::Runtime::Providers::OpenRouter).to receive(:new).and_return(openrouter_provider)
    allow(openrouter_provider).to receive(:chat_completions).and_return({ "choices" => [] })

    client.complete(model: "meta-llama/llama-3.3-8b-instruct:free", messages: [], params: {}, stream: nil, openai_override: nil)

    expect(openrouter_provider).to have_received(:chat_completions)
  end

  it "forces OpenAI when openai_override is provided" do
    openai_provider = instance_double(Raix::Runtime::Providers::OpenAI)
    allow(Raix::Runtime::Providers::OpenAI).to receive(:new).and_return(openai_provider)
    allow(openai_provider).to receive(:chat_completions).and_return({ "choices" => [] })

    client.complete(model: "meta-llama/llama-3.3-8b-instruct:free", messages: [], params: {}, stream: nil, openai_override: "gpt-4o-mini")

    expect(openai_provider).to have_received(:chat_completions)
  end

  it "uses a legacy client when configured" do
    legacy_client = double("legacy_client")
    configuration.openrouter_client = legacy_client

    expect(legacy_client).to receive(:complete).with(
      model: "meta-llama/llama-3.3-8b-instruct:free",
      messages: [],
      params: {},
      stream: nil
    ).and_return({ "choices" => [] })

    expect do
      client.complete(model: "meta-llama/llama-3.3-8b-instruct:free", messages: [], params: {}, stream: nil, openai_override: nil)
    end.to output(/DEPRECATION: `openrouter_client`/).to_stderr
  end
end
