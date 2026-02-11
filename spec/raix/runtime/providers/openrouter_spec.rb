# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::Runtime::Providers::OpenRouter do
  let(:configuration) { Raix::Configuration.new(fallback: nil) }
  let(:transport) { instance_double(Raix::Runtime::Transport) }
  subject(:provider) { described_class.new(configuration:, transport:) }

  before do
    configuration.openrouter_api_key = "openrouter-key"
  end

  it "sends sync requests through transport.post_json" do
    expect(transport).to receive(:post_json).with(
      url: "https://openrouter.ai/api/v1/chat/completions",
      headers: hash_including("Authorization" => "Bearer openrouter-key"),
      payload: hash_including(model: "meta-llama/llama-3.3-8b-instruct:free", messages: [{ role: "user", content: "Hi" }]),
      provider: "openrouter"
    ).and_return({ "choices" => [] })

    provider.chat_completions(model: "meta-llama/llama-3.3-8b-instruct:free", messages: [{ role: "user", content: "Hi" }], params: {}, stream: nil)
  end

  it "sends stream requests through transport.post_stream" do
    callback = proc {}

    expect(transport).to receive(:post_stream).and_return({ "choices" => [] })
    provider.chat_completions(model: "meta-llama/llama-3.3-8b-instruct:free", messages: [], params: {}, stream: callback)
  end

  it "raises when API key is missing" do
    configuration.openrouter_api_key = nil

    expect do
      provider.chat_completions(model: "meta-llama/llama-3.3-8b-instruct:free", messages: [], params: {}, stream: nil)
    end.to raise_error(Raix::Runtime::ConfigurationError, /Missing OpenRouter API key/)
  end
end
