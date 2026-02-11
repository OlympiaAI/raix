# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::Runtime::Providers::OpenAI do
  let(:configuration) { Raix::Configuration.new(fallback: nil) }
  let(:transport) { instance_double(Raix::Runtime::Transport) }
  subject(:provider) { described_class.new(configuration:, transport:) }

  before do
    configuration.openai_api_key = "openai-key"
    configuration.openai_organization_id = "org_123"
    configuration.openai_project_id = "proj_123"
  end

  it "sends sync requests through transport.post_json" do
    expect(transport).to receive(:post_json).with(
      url: "https://api.openai.com/v1/chat/completions",
      headers: hash_including(
        "Authorization" => "Bearer openai-key",
        "OpenAI-Organization" => "org_123",
        "OpenAI-Project" => "proj_123"
      ),
      payload: hash_including(model: "gpt-4o", messages: [{ role: "user", content: "Hi" }]),
      provider: "openai"
    ).and_return({ "choices" => [] })

    provider.chat_completions(model: "gpt-4o", messages: [{ role: "user", content: "Hi" }], params: {}, stream: nil)
  end

  it "sends stream requests through transport.post_stream" do
    callback = proc {}

    expect(transport).to receive(:post_stream).and_return({ "choices" => [] })
    provider.chat_completions(model: "gpt-4o", messages: [], params: {}, stream: callback)
  end

  it "raises when API key is missing" do
    configuration.openai_api_key = nil

    expect do
      provider.chat_completions(model: "gpt-4o", messages: [], params: {}, stream: nil)
    end.to raise_error(Raix::Runtime::ConfigurationError, /Missing OpenAI API key/)
  end
end
