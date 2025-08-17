# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::Providers::OpenAIProvider do
  let(:openai_client) { double("OpenAI Client") }
  let(:messages) { [{ role: "user", content: "Hello" }] }
  let(:provider) { described_class.new(openai_client) }

  it "wraps the OpenAI client" do
    expect(provider.client).to eq(openai_client)
  end

  it "implements request method that calls the client's chat method" do
    expected_params = {
      temperature: 0.7,
      max_completion_tokens: 1000,
      stream: true,
      stream_options: { include_usage: true },
      model: "gpt-4",
      messages:
    }

    expect(openai_client).to receive(:chat).with(
      parameters: expected_params
    ).and_return({ "choices" => [{ "message" => { "content" => "Response" } }] })

    result = provider.request(
      params: { temperature: 0.7, max_completion_tokens: 1000, stream: true },
      model: "gpt-4",
      messages:
    )

    expect(result).to eq({ "choices" => [{ "message" => { "content" => "Response" } }] })
  end

  it "removes temperature for o-models" do
    expect(openai_client).to receive(:chat).with(
      parameters: { max_completion_tokens: 1000, model: "o1-preview", messages: }
    ).and_return({ "choices" => [] })

    provider.request(
      params: { temperature: 0.7, max_completion_tokens: 1000 },
      model: "o1-preview",
      messages:
    )
  end

  it "handles prediction parameters correctly" do
    prediction_params = {
      prediction: { type: "content", content: "predicted text" },
      stream: false,
      model: "gpt-4",
      messages:
    }

    expect(openai_client).to receive(:chat).with(
      parameters: prediction_params
    ).and_return({ "choices" => [] })

    provider.request(
      params: prediction_params.merge(max_completion_tokens: 1000),
      model: "gpt-4",
      messages:
    )
  end
end
