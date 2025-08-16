# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::Providers::OpenRouterProvider do
  let(:openrouter_client) { double("OpenRouter Client") }
  let(:messages) { [{ role: "user", content: "Hello" }] }
  let(:provider) { described_class.new(openrouter_client) }

  it "wraps the OpenRouter client" do
    expect(provider.client).to eq(openrouter_client)
  end

  it "implements request method that calls the client's complete method" do
    expect(openrouter_client).to receive(:complete).with(
      messages,
      model: "claude-3-opus",
      extras: { temperature: 0.7 },
      stream: false
    ).and_return({ "choices" => [{ "message" => { "content" => "Response" } }] })

    result = provider.request(
      params: { temperature: 0.7, max_completion_tokens: 1000, stream: false },
      model: "claude-3-opus",
      messages:
    )

    expect(result).to eq({ "choices" => [{ "message" => { "content" => "Response" } }] })
  end

  it "removes max_completion_tokens parameter" do
    expect(openrouter_client).to receive(:complete).with(
      messages,
      model: "claude-3-opus",
      extras: { temperature: 0.7 },
      stream: false
    ).and_return({ "choices" => [] })

    provider.request(
      params: { temperature: 0.7, max_completion_tokens: 1000, stream: false },
      model: "claude-3-opus",
      messages:
    )
  end

  it "handles retry logic for server errors" do
    call_count = 0
    allow(openrouter_client).to receive(:complete) do
      call_count += 1
      raise OpenRouter::ServerError, "Please retry" if call_count < 3

      { "choices" => [{ "message" => { "content" => "Success" } }] }
    end

    result = provider.request(
      params: { stream: false },
      model: "claude-3-opus",
      messages:
    )

    expect(result).to eq({ "choices" => [{ "message" => { "content" => "Success" } }] })
    expect(call_count).to eq(3)
  end
end
