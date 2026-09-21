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
      tokens: RubyLLM::Tokens.new(input: 1234, output: 56),
      model: "google/gemini-3-flash-preview",
      raw_reasoning: nil,
      thinking: nil,
      raw: raw_response
    )
  end

  let(:fake_chat) do
    instance_double(
      "RubyLLM::Chat",
      with_instructions: nil,
      add_message: nil,
      with_temperature: nil,
      with_max_output_tokens: nil,
      with_provider_options: nil,
      with_caching: nil,
      with_tools: nil,
      generate: fake_response_message
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

  it "tolerates a provider that does not expose a raw body (falls back to the message model)" do
    barebones_message = instance_double(
      "RubyLLM::Message",
      content: "ok",
      tool_calls: nil,
      tool_call?: false,
      tokens: RubyLLM::Tokens.new(input: 1, output: 1),
      model: "fallback-model",
      raw_reasoning: nil,
      thinking: nil,
      raw: nil
    )
    allow(fake_chat).to receive(:generate).and_return(barebones_message)

    response = instance.send(:ruby_llm_request, params: {}, model: "fallback-model", messages: [{ role: "user", content: "hi" }])

    expect(response["id"]).to be_nil
    expect(response["model"]).to eq("fallback-model")
    expect(response.dig("usage", "prompt_tokens")).to eq(1)
  end

  it "warns instead of silently dropping a message whose role RubyLLM does not support" do
    messages = [{ role: "user", content: "hi" }, { role: "function", name: "legacy", content: "result" }]

    expect do
      instance.send(:ruby_llm_request, params: {}, model: "m", messages:)
    end.to output(/unsupported role "function"/).to_stderr

    expect(fake_chat).to have_received(:add_message).once
  end

  it "forwards the output token ceiling to RubyLLM, preferring max_completion_tokens" do
    instance.send(:ruby_llm_request, params: { max_tokens: 50, max_completion_tokens: 20 }, model: "m", messages: [{ role: "user", content: "hi" }])
    expect(fake_chat).to have_received(:with_max_output_tokens).with(20)

    instance.send(:ruby_llm_request, params: { max_tokens: 50 }, model: "m", messages: [{ role: "user", content: "hi" }])
    expect(fake_chat).to have_received(:with_max_output_tokens).with(50)
  end

  it "prefers the provider's prompt_tokens over RubyLLM's uncached input count" do
    cached_response = instance_double(
      "Faraday::Response",
      body: { "usage" => { "prompt_tokens" => 1000, "completion_tokens" => 20, "total_tokens" => 1020, "prompt_tokens_details" => { "cached_tokens" => 900 } } }
    )
    cached_message = instance_double(
      "RubyLLM::Message",
      content: "ok",
      tool_calls: nil,
      tool_call?: false,
      tokens: RubyLLM::Tokens.new(input: 100, output: 20, cache_read: 900),
      model: "cached-model",
      raw_reasoning: nil,
      thinking: nil,
      raw: cached_response
    )
    allow(fake_chat).to receive(:generate).and_return(cached_message)

    response = instance.send(:ruby_llm_request, params: {}, model: "cached-model", messages: [{ role: "user", content: "hi" }])

    expect(response["usage"]).to include("prompt_tokens" => 1000, "completion_tokens" => 20, "total_tokens" => 1020)
    expect(response.dig("usage", "prompt_tokens_details", "cached_tokens")).to eq(900)
  end

  it "counts cached tokens into prompt_tokens when the provider gives no usage" do
    cached_message = instance_double(
      "RubyLLM::Message",
      content: "ok",
      tool_calls: nil,
      tool_call?: false,
      tokens: RubyLLM::Tokens.new(input: 100, output: 20, cache_read: 900),
      model: "cached-model",
      raw_reasoning: nil,
      thinking: nil,
      raw: nil
    )
    allow(fake_chat).to receive(:generate).and_return(cached_message)

    response = instance.send(:ruby_llm_request, params: {}, model: "cached-model", messages: [{ role: "user", content: "hi" }])

    expect(response["usage"]).to eq("prompt_tokens" => 1000, "completion_tokens" => 20, "total_tokens" => 1020)
  end

  it "carries signed reasoning on the response and back into a replayed assistant turn" do
    thinking = Struct.new(:text, :signature).new("let me think", "thinking-sig")
    reasoning_message = instance_double(
      "RubyLLM::Message",
      content: "ok",
      tool_calls: nil,
      tool_call?: false,
      tokens: RubyLLM::Tokens.new(input: 1, output: 1),
      model: "reasoning-model",
      raw_reasoning: [{ "type" => "reasoning.text", "text" => "let me think" }],
      thinking:,
      raw: nil
    )
    allow(fake_chat).to receive(:generate).and_return(reasoning_message)

    response = instance.send(:ruby_llm_request, params: {}, model: "reasoning-model", messages: [{ role: "user", content: "hi" }])
    turn = response.dig("choices", 0, "message")

    expect(turn).to include(
      "raw_reasoning" => [{ "type" => "reasoning.text", "text" => "let me think" }],
      "thinking" => "let me think",
      "thinking_signature" => "thinking-sig"
    )

    instance.send(:ruby_llm_request, params: {}, model: "reasoning-model", messages: [{ role: "user", content: "hi" }, turn])

    expect(fake_chat).to have_received(:add_message).with(
      hash_including(role: :assistant, raw_reasoning: turn["raw_reasoning"], thinking: "let me think", thinking_signature: "thinking-sig")
    )
  end

  it "serializes a real Hash of RubyLLM::ToolCall into OpenAI-shaped tool_calls" do
    tool_calls = {
      "call_abc" => RubyLLM::ToolCall.new(id: "call_abc", name: "get_weather", arguments: { "city" => "Boston" })
    }
    message_with_tool_calls = instance_double(
      "RubyLLM::Message",
      content: nil,
      tool_calls:,
      tool_call?: true,
      tokens: RubyLLM::Tokens.new(input: 3, output: 4),
      model: "google/gemini-3-flash-preview",
      raw_reasoning: nil,
      thinking: nil,
      raw: raw_response
    )
    allow(fake_chat).to receive(:generate).and_return(message_with_tool_calls)

    response = instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages: [{ role: "user", content: "weather?" }])

    serialized = response.dig("choices", 0, "message", "tool_calls")
    expect(serialized).to eq(
      [
        {
          "id" => "call_abc",
          "type" => "function",
          "function" => {
            "name" => "get_weather",
            "arguments" => { "city" => "Boston" }.to_json
          }
        }
      ]
    )
  end

  it "reports nil tool_calls when RubyLLM hands back an empty Hash rather than nil" do
    message_without_calls = instance_double(
      "RubyLLM::Message",
      content: "no tools needed",
      tool_calls: {},
      tool_call?: false,
      tokens: RubyLLM::Tokens.new(input: 3, output: 4),
      model: "google/gemini-3-flash-preview",
      raw_reasoning: nil,
      thinking: nil,
      raw: raw_response
    )
    allow(fake_chat).to receive(:generate).and_return(message_without_calls)

    response = instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages: [{ role: "user", content: "hi" }])

    expect(response.dig("choices", 0, "message", "tool_calls")).to be_nil
    expect(response.dig("choices", 0, "finish_reason")).to eq("stop")
  end

  it "normalizes replayed OpenAI-shaped tool_calls with JSON-string arguments into RubyLLM::ToolCall for add_message" do
    replayed_messages = [
      { role: "user", content: "please work" },
      {
        role: "assistant",
        content: nil,
        tool_calls: [
          { id: "call_1", type: "function", function: { name: "do_work", arguments: '{"n":1}' } }
        ]
      }
    ]

    instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages: replayed_messages)

    expect(fake_chat).to have_received(:add_message).with(
      hash_including(
        role: :assistant,
        tool_calls: {
          "call_1" => an_object_having_attributes(id: "call_1", name: "do_work", arguments: { "n" => 1 })
        }
      )
    )
  end

  context "when a provider returns an unsolicited tool call to a class with no functions" do
    let(:unsolicited) do
      instance_double(
        "RubyLLM::Message",
        content: nil,
        tool_calls: { "call_x" => RubyLLM::ToolCall.new(id: "call_x", name: "do_anything", arguments: {}) },
        tool_call?: true,
        tokens: RubyLLM::Tokens.new(input: 1, output: 1),
        model: "google/gemini-3-flash-preview",
        raw_reasoning: nil,
        thinking: nil,
        raw: nil
      )
    end

    before do
      allow(fake_chat).to receive(:generate).and_return(unsolicited, fake_response_message)
      allow(fake_chat).to receive(:add_message).and_return(instance_double("RubyLLM::Message", cache_until_here: nil))
    end

    it "refuses the call and still reaches a final answer" do
      response = instance.chat_completion(messages: [{ user: "hi" }])

      expect(response).to eq("the answer is 42")
      expect(fake_chat).to have_received(:add_message).with(
        hash_including(role: :tool, tool_call_id: "call_x", content: "Tool call refused: do_anything is not available on this request.")
      )
    end
  end

  context "with multimodal content and cache boundaries" do
    let(:red_png_base64) do
      "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEUlEQVR4nGP8z8Dwn4EIwDiqEAAQOAQBjEZ1pgAAAABJRU5ErkJggg=="
    end
    let(:data_uri) { "data:image/png;base64,#{red_png_base64}" }
    let(:added_message) { instance_double("RubyLLM::Message", cache_until_here: nil) }

    before do
      allow(fake_chat).to receive(:add_message).and_return(added_message)
    end

    it "wires structured user content into add_message with joined text and attachments" do
      messages = [
        {
          role: "user",
          content: [
            { type: "text", text: "What color is this?" },
            { type: "image_url", image_url: { url: data_uri } }
          ]
        }
      ]

      instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages:)

      expect(fake_chat).to have_received(:add_message).with(
        role: :user,
        content: "What color is this?",
        attachments: array_including(kind_of(StringIO))
      )
    end

    it "sends an empty string rather than no content when every image_url part was skipped" do
      messages = [
        { role: "user", content: [{ type: "image_url", image_url: { url: "/etc/hostname" } }] }
      ]

      instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages:)

      expect(fake_chat).to have_received(:add_message).with(role: :user, content: "", attachments: [])
    end

    it "sends an empty string for an assistant turn with neither content nor tool calls" do
      instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview",
                                       messages: [{ role: "user", content: "hi" }, { role: "assistant", content: [] }])

      expect(fake_chat).to have_received(:add_message).with(role: :assistant, content: "")
    end

    it "sends an empty string for an empty content array" do
      instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages: [{ role: "user", content: [] }])

      expect(fake_chat).to have_received(:add_message).with(role: :user, content: "", attachments: [])
    end

    it "leaves content nil when the message is image-only, so RubyLLM builds the parts itself" do
      messages = [
        { role: "user", content: [{ type: "image_url", image_url: { url: data_uri } }] }
      ]

      instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages:)

      expect(fake_chat).to have_received(:add_message).with(
        role: :user,
        content: nil,
        attachments: array_including(kind_of(StringIO))
      )
    end

    it "marks a message carrying cache_control as a cache boundary and enables caching on the chat" do
      messages = [
        {
          role: "user",
          content: [
            { type: "text", text: "the long bit", cache_control: { type: "ephemeral" } }
          ]
        }
      ]

      instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages:)

      expect(added_message).to have_received(:cache_until_here)
      expect(fake_chat).to have_received(:with_caching).with({})
    end

    it "forwards a cache_control ttl to RubyLLM's caching options" do
      messages = [
        {
          role: "user",
          content: [{ type: "text", text: "the long bit", cache_control: { type: "ephemeral", ttl: "1h" } }]
        }
      ]

      instance.send(:ruby_llm_request, params: {}, model: "google/gemini-3-flash-preview", messages:)

      expect(fake_chat).to have_received(:with_caching).with(ttl: "1h")
    end
  end
end
