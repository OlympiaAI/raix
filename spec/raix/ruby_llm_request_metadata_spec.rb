# frozen_string_literal: true

# Regression coverage for the OpenAI-compatible response that
# `ruby_llm_request` returns. The non-streaming branch used to hand-build a
# hash with only `choices` and `usage`, dropping the upstream `id`, `model`,
# and `usage.prompt_tokens_details` that callers need to look up authoritative
# billing cost (e.g. via OpenRouter's /api/v1/generation) or to verify
# prompt-cache hits. See README of the consumer app: silent cost loss
# manifested as zero `cost_usd` on every distillation until this gap was
# closed.
class DummyMeaningOfLife
  include Raix::ChatCompletion
end

RSpec.describe Raix::ChatCompletion, "#ruby_llm_request response shape" do
  let(:instance) { DummyMeaningOfLife.new }

  let(:raw_response) do
    instance_double(
      "Faraday::Response",
      body: {
        "id" => "gen-2026-test-abc",
        "model" => "google/gemini-3-flash-preview",
        "provider" => "Google",
        "usage" => {
          "prompt_tokens" => 1234,
          "completion_tokens" => 56,
          "total_tokens" => 1290,
          "prompt_tokens_details" => { "cached_tokens" => 1024 }
        }
      }
    )
  end

  let(:fake_response_message) do
    instance_double(
      "RubyLLM::Message",
      content: "the answer is 42",
      tool_calls: nil,
      tool_call?: false,
      input_tokens: 1234,
      output_tokens: 56,
      model_id: "google/gemini-3-flash-preview",
      raw: raw_response
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

  before do
    allow(RubyLLM).to receive(:chat).and_return(fake_chat)
  end

  it "preserves the upstream generation id, model, and provider on the response" do
    response = instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages: [{ role: "user", content: "hi" }])

    expect(response["id"]).to eq("gen-2026-test-abc")
    expect(response["model"]).to eq("google/gemini-3-flash-preview")
    expect(response["provider"]).to eq("Google")
  end

  it "merges upstream usage details (cached tokens) alongside the basic counts" do
    response = instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages: [{ role: "user", content: "hi" }])

    expect(response.dig("usage", "prompt_tokens")).to eq(1234)
    expect(response.dig("usage", "completion_tokens")).to eq(56)
    expect(response.dig("usage", "total_tokens")).to eq(1290)
    expect(response.dig("usage", "prompt_tokens_details", "cached_tokens")).to eq(1024)
  end

  it "still returns the OpenAI-compatible choices array" do
    response = instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages: [{ role: "user", content: "hi" }])

    expect(response.dig("choices", 0, "message", "content")).to eq("the answer is 42")
    expect(response.dig("choices", 0, "finish_reason")).to eq("stop")
  end

  it "tolerates a provider that does not expose a raw body (falls back to message model_id)" do
    barebones_message = instance_double(
      "RubyLLM::Message",
      content: "ok",
      tool_calls: nil,
      tool_call?: false,
      input_tokens: 1,
      output_tokens: 1,
      model_id: "fallback-model",
      raw: nil
    )
    allow(fake_chat).to receive(:complete).and_return(barebones_message)
    allow(fake_chat).to receive(:ask).and_return(barebones_message)

    response = instance.send(:ruby_llm_request, params: {}, model: "fallback-model", messages: [{ role: "user", content: "hi" }])

    expect(response["id"]).to be_nil
    expect(response["model"]).to eq("fallback-model")
    expect(response.dig("usage", "prompt_tokens")).to eq(1)
  end
end
