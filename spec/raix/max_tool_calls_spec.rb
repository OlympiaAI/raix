# frozen_string_literal: true

# Regression coverage for max_tool_calls enforcement.
#
# Raix drives the tool-call loop itself: each request asks RubyLLM for exactly
# one completion (`generate`), Raix dispatches whatever tool calls come back,
# appends the exchange to the transcript, and asks again. The budget is counted
# per tool call, so a response packing several parallel calls can be cut off
# partway through. Once the budget is spent — or a tool calls
# `stop_tool_calls_and_respond!` — Raix issues one final completion with no
# tools registered.

# A fake RubyLLM::Chat that records what Raix does to it and lets each spec
# script what `generate` returns. The same instance is handed back for every
# `RubyLLM.chat` call (transcript memo + each request), matching how the real
# backend reuses one conversation. `generate` invokes the provided behavior
# with the chat and the 1-based completion number, so a spec can hand back tool
# calls on the first passes and a final message on the last.
class ScriptedRubyLLMChat
  # Stand-in for the Message returned by add_message. Raix only ever calls
  # #cache_until_here on it.
  class AddedMessage
    def cache_until_here = self
  end

  attr_reader :instructions, :tools, :generate_count, :tool_count_at_generate, :requests

  def initialize(&behavior)
    @behavior = behavior
    @instructions = []
    @tools = {}
    @generate_count = 0
    @tool_count_at_generate = []
    # Per-completion capture: each entry records the instructions and messages
    # applied to this chat since the previous completion, so a spec can inspect
    # exactly what the forced final (tool-less) request was rebuilt from.
    @requests = []
    @current_instructions = []
    @current_messages = []
    @current_provider_options = {}
    @current_tools_registered = 0
  end

  def with_instructions(content, **)
    @instructions << content
    @current_instructions << content
    self
  end

  def add_message(attrs)
    @current_messages << attrs
    AddedMessage.new
  end

  def messages = []

  def messages=(_new_messages)
    []
  end

  def with_temperature(_) = self
  def with_max_output_tokens(_) = self
  def with_caching(*) = self

  def with_provider_options(options)
    @current_provider_options = options.to_h
    self
  end

  def with_tools(*tools)
    tools.flatten.compact.each do |tool|
      @tools[tool.name.to_sym] = tool
      @current_tools_registered += 1
    end
    self
  end

  def generate(&)
    @generate_count += 1
    @tool_count_at_generate << @tools.size
    result = @behavior.call(self, @generate_count)
    @requests << {
      instructions: @current_instructions.dup,
      messages: @current_messages.dup,
      provider_options: @current_provider_options.dup,
      tools_registered: @current_tools_registered
    }
    @current_instructions = []
    @current_messages = []
    @current_provider_options = {}
    @current_tools_registered = 0
    result
  end
end

class ToolBudgetProbe
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  attr_reader :work_executions, :finish_executions

  function :do_work, "does a unit of work", n: { type: "integer" } do |_args|
    @work_executions += 1
    "work result #{@work_executions}"
  end

  function :finish_now, "wrap things up" do |_args|
    @finish_executions += 1
    stop_tool_calls_and_respond!
    "stopping"
  end

  def initialize
    @work_executions = 0
    @finish_executions = 0
    transcript << { user: "please work" }
  end
end

# Exercises the documented `messages:` argument, which drives the request
# without ever being written into the transcript.
class ExplicitMessagesProbe
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  attr_reader :work_executions

  function :do_work, "does a unit of work", n: { type: "integer" } do |_args|
    @work_executions += 1
    "work result #{@work_executions}"
  end

  def initialize
    @work_executions = 0
  end
end

# A tool body that calls chat_completion again on the same instance, the way
# a sub-agent tool would. The nested loop must not disturb the outer one.
class NestingProbe
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  attr_reader :inner_result, :work_executions

  function :do_work, "does a unit of work", n: { type: "integer" } do |_args|
    @work_executions += 1
    "work result #{@work_executions}"
  end

  function :delegate, "hand a question to a nested completion" do |_args|
    @inner_result = chat_completion(
      messages: [{ user: "inner question" }],
      params: { tool_choice: "required" },
      max_tool_calls: 1,
      available_tools: [:do_work],
      save_response: false
    )
    "delegated"
  end

  function :boom, "a tool that fails" do |_args|
    raise "boom"
  end

  function :bad_json, "a tool whose own JSON parsing fails" do |_args|
    JSON.parse("<html>not a valid JSON document token=SECRET</html>")
  end

  function :finish_now, "wrap things up" do |_args|
    stop_tool_calls_and_respond!
    "stopping"
  end

  function :delegate_to_stopper, "run a nested completion whose tool stops" do |_args|
    chat_completion(messages: [{ user: "inner question" }], max_tool_calls: 5, available_tools: [:finish_now], save_response: false)
    "delegated"
  end

  function :delegate_then_stop, "run a nested completion, then request a stop" do |_args|
    chat_completion(messages: [{ user: "inner question" }], max_tool_calls: 5, available_tools: [:do_work], save_response: false)
    stop_tool_calls_and_respond!
    "delegated then stopped"
  end

  function :delegate_to_capped, "run a nested completion with a budget of one" do |_args|
    @inner_result = chat_completion(messages: [{ user: "inner question" }], max_tool_calls: 1, available_tools: [:do_work], save_response: false)
    "delegated"
  end

  function :stop_then_delegate_to_boom, "request a stop, then run a nested completion whose tool raises" do |_args|
    stop_tool_calls_and_respond!
    chat_completion(messages: [{ user: "inner question" }], max_tool_calls: 5, available_tools: [:boom], save_response: false)
    "unreachable"
  end

  function :stop_then_delegate, "request a stop, then run a nested completion" do |_args|
    stop_tool_calls_and_respond!
    chat_completion(messages: [{ user: "inner question" }], max_tool_calls: 1, available_tools: [:do_work], save_response: false)
    "stopped"
  end

  def initialize
    @work_executions = 0
    transcript << { user: "outer question" }
  end
end

# PromptDeclarations overrides chat_completion with a narrower signature, so
# continuation rounds must not re-enter the public method.
class PromptToolProbe
  include Raix::ChatCompletion
  include Raix::FunctionDispatch
  include Raix::PromptDeclarations

  attr_reader :work_executions

  function :do_work, "does a unit of work", n: { type: "integer" } do |_args|
    @work_executions += 1
    "work result #{@work_executions}"
  end

  prompt text: -> { "please work" }

  def initialize
    @work_executions = 0
  end
end

RSpec.describe Raix::ChatCompletion, "max_tool_calls enforcement" do
  subject(:probe) { ToolBudgetProbe.new }

  def message_double(content:, tool_calls:, raw_reasoning: nil)
    instance_double(
      "RubyLLM::Message",
      content:,
      tool_calls:,
      tool_call?: !tool_calls.nil?,
      tokens: RubyLLM::Tokens.new(input: 5, output: 5),
      model: "test-model",
      raw_reasoning:,
      thinking: nil,
      raw: nil
    )
  end

  def final_message(content)
    message_double(content:, tool_calls: nil)
  end

  # A model response requesting `count` calls to `tool_name`, the way RubyLLM
  # hands them back: a Hash keyed by call id.
  def tool_call_message(tool_name, count: 1, arguments: nil, thought_signature: nil, raw_reasoning: nil)
    calls = Array.new(count) do |i|
      RubyLLM::ToolCall.new(id: "call_#{tool_name}_#{i}", name: tool_name.to_s, arguments: arguments || { "n" => i }, thought_signature:)
    end

    message_double(content: nil, tool_calls: calls.to_h { |call| [call.id, call] }, raw_reasoning:)
  end

  # A single model response calling several different tools, in order.
  def mixed_tool_call_message(*tool_names)
    calls = tool_names.each_with_index.map do |tool_name, i|
      RubyLLM::ToolCall.new(id: "call_#{tool_name}_#{i}", name: tool_name.to_s, arguments: { "n" => i })
    end

    message_double(content: nil, tool_calls: calls.to_h { |call| [call.id, call] })
  end

  def tool_contents(request)
    request[:messages].select { |m| m[:role] == :tool }.map { |m| m[:content] }
  end

  let(:fake_chat) { ScriptedRubyLLMChat.new(&behavior) }

  before { allow(RubyLLM).to receive(:chat).and_return(fake_chat) }

  context "when the model keeps calling tools past the budget" do
    # One call per round; the model never stops asking for more.
    let(:behavior) do
      lambda do |_chat, n|
        n <= 3 ? tool_call_message(:do_work) : final_message("final answer after cap")
      end
    end

    it "refuses the tool call that exceeds max_tool_calls and returns a forced final response" do
      response = probe.chat_completion(max_tool_calls: 2)

      expect(response).to eq("final answer after cap")
      # do_work ran exactly twice (rounds 1 and 2); the 3rd was refused.
      expect(probe.work_executions).to eq(2)
    end

    it "issues the final completion without tools and injects the limit system message" do
      probe.chat_completion(max_tool_calls: 2)

      # Three tool rounds, then the forced final completion.
      expect(fake_chat.generate_count).to eq(4)
      expect(fake_chat.instructions).to include(a_string_matching(/Maximum tool calls \(2\) exceeded/))
      # The final request carries no tool_choice and its own system message.
      expect(fake_chat.requests.last[:instructions]).to include(a_string_matching(/Maximum tool calls/))
    end
  end

  context "when a single response packs several parallel tool calls" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work, count: 5) : final_message("final answer parallel")
      end
    end

    it "enforces the cap per call so the round cannot blow past it" do
      response = probe.chat_completion(max_tool_calls: 2)

      expect(response).to eq("final answer parallel")
      # Only the first 2 of the 5 parallel calls ran; the rest were refused.
      expect(probe.work_executions).to eq(2)
      expect(fake_chat.generate_count).to eq(2)
    end

    it "answers every tool call in the replayed exchange, refusals included" do
      probe.chat_completion(max_tool_calls: 2)

      results = tool_contents(fake_chat.requests.last)
      expect(results.size).to eq(5)
      expect(results.grep(/work result/).size).to eq(2)
      expect(results.grep(/refused: maximum tool calls \(2\)/).size).to eq(3)
    end
  end

  context "when the model's turn carries signed reasoning" do
    let(:behavior) do
      lambda do |_chat, n|
        if n == 1
          tool_call_message(:do_work, thought_signature: "sig-1", raw_reasoning: [{ "type" => "reasoning.text", "text" => "thinking" }])
        else
          final_message("reasoned answer")
        end
      end
    end

    it "replays the model's own assistant turn, ids and signatures intact, ahead of the tool results" do
      probe.chat_completion(max_tool_calls: 5)

      continuation = fake_chat.requests[1][:messages]
      assistant = continuation.find { |m| m[:role] == :assistant }
      expect(assistant[:raw_reasoning]).to eq([{ "type" => "reasoning.text", "text" => "thinking" }])
      expect(assistant[:tool_calls].keys).to eq(["call_do_work_0"])
      expect(assistant[:tool_calls]["call_do_work_0"].thought_signature).to eq("sig-1")

      tool_result = continuation.find { |m| m[:role] == :tool }
      expect(tool_result[:tool_call_id]).to eq("call_do_work_0")
      expect(tool_result[:content]).to eq("work result 1")
    end
  end

  context "when the round is over" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work, thought_signature: "sig-1") : final_message("recorded")
      end
    end

    it "stores the model's own tool-call turn and result in the transcript for later replay" do
      probe.chat_completion(max_tool_calls: 5)

      recorded = probe.transcript.flatten
      assistant = recorded.find { |m| m[:role] == "assistant" && m[:tool_calls] }
      expect(assistant[:tool_calls].first).to include("id" => "call_do_work_0", "thought_signature" => "sig-1")
      tool = recorded.find { |m| m[:role] == "tool" }
      expect(tool).to include(tool_call_id: "call_do_work_0", content: "work result 1")
      expect(recorded.last).to eq(assistant: "recorded")
    end
  end

  context "when the class also includes PromptDeclarations" do
    subject(:probe) { PromptToolProbe.new }

    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work) : final_message("prompted answer")
      end
    end

    it "runs the tool round and returns the prompt's final answer" do
      response = probe.chat_completion

      expect(response).to eq("prompted answer")
      expect(probe.work_executions).to eq(1)
      expect(fake_chat.generate_count).to eq(2)
    end
  end

  context "when the model sends arguments that are not a JSON object" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work, arguments: []) : final_message("recovered from bad args")
      end
    end

    it "hands the model a tool error instead of running the function or crashing" do
      response = probe.chat_completion(max_tool_calls: 5)

      expect(response).to eq("recovered from bad args")
      expect(probe.work_executions).to eq(0)
      expect(tool_contents(fake_chat.requests[1])).to eq(["Invalid arguments for do_work: expected a JSON object, got Array"])
    end
  end

  context "when the provider returns tool arguments that are not valid JSON" do
    let(:broken_arguments) { "{" }
    let(:raw_response) do
      instance_double(
        "Faraday::Response",
        body: {
          "id" => "gen-broken",
          "model" => "test-model",
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => nil,
                "reasoning_details" => [{ "type" => "reasoning.text", "text" => "hmm" }],
                "tool_calls" => [
                  {
                    "id" => "call_broken",
                    "type" => "function",
                    "function" => { "name" => "do_work", "arguments" => broken_arguments },
                    "extra_content" => { "google" => { "thought_signature" => "gemini-sig" } }
                  }
                ]
              }
            }
          ],
          "usage" => { "prompt_tokens" => 7, "completion_tokens" => 3, "total_tokens" => 10 }
        }
      )
    end

    let(:behavior) do
      lambda do |_chat, n|
        raise RubyLLM::ToolCallParseError.new(response: raw_response, finish_reason: :tool_calls) if n == 1

        final_message("recovered from malformed json")
      end
    end

    it "answers the call with a tool error and continues" do
      response = probe.chat_completion(max_tool_calls: 5)

      expect(response).to eq("recovered from malformed json")
      expect(probe.work_executions).to eq(0)
      # The fake records a request only when generate returns, so the raising
      # first round leaves a single entry: the continuation.
      continuation = fake_chat.requests.last
      assistant = continuation[:messages].find { |m| m[:role] == :assistant }
      expect(assistant[:tool_calls].keys).to eq(["call_broken"])
      expect(tool_contents(continuation)).to eq(["Invalid arguments for do_work: malformed JSON"])
    end

    it "keeps the signed state the raw payload carried" do
      probe.chat_completion(max_tool_calls: 5)

      assistant = fake_chat.requests.last[:messages].find { |m| m[:role] == :assistant }
      expect(assistant[:raw_reasoning]).to eq([{ "type" => "reasoning.text", "text" => "hmm" }])
      expect(assistant[:tool_calls]["call_broken"].thought_signature).to eq("gemini-sig")
    end

    context "and the payload repeats a tool call id" do
      let(:raw_response) do
        call = { "id" => "call_dup", "type" => "function", "function" => { "name" => "do_work", "arguments" => "{" } }
        instance_double("Faraday::Response", body: { "choices" => [{ "message" => { "role" => "assistant", "tool_calls" => [call, call] } }] })
      end

      it "gives up on recovery and lets the parse error propagate" do
        expect { probe.chat_completion(max_tool_calls: 5) }.to raise_error(RubyLLM::ToolCallParseError)
        expect(probe.work_executions).to eq(0)
      end
    end

    context "and the arguments are only whitespace" do
      let(:broken_arguments) { " \n\t " }

      it "treats them as malformed rather than as no arguments" do
        probe.chat_completion(max_tool_calls: 5)

        expect(probe.work_executions).to eq(0)
        expect(tool_contents(fake_chat.requests.last)).to eq(["Invalid arguments for do_work: malformed JSON"])
      end
    end
  end

  context "when streaming" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work) : final_message("streamed answer")
      end
    end

    it "still dispatches tool calls and returns the final content" do
      probe.stream = proc { |_chunk| }

      response = probe.chat_completion(max_tool_calls: 5)

      expect(response).to eq("streamed answer")
      expect(probe.work_executions).to eq(1)
      expect(fake_chat.generate_count).to eq(2)
    end
  end

  context "when json: true and the budget trips" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work) : final_message('{"ok": true}')
      end
    end

    it "parses the forced final response like any other" do
      response = probe.chat_completion(json: true, max_tool_calls: 0)

      expect(response).to eq("ok" => true)
      expect(Thread.current[:chat_completion_response].dig(:choices, 0, :message, :content)).to eq('{"ok": true}')
    end
  end

  context "when a prediction is configured" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work) : final_message("predicted")
      end
    end

    it "sends the same single-wrapped prediction on every round" do
      probe.prediction = "guess"

      probe.chat_completion(max_tool_calls: 5)

      expected = { type: "content", content: "guess" }
      expect(fake_chat.requests[0][:provider_options][:prediction]).to eq(expected)
      expect(fake_chat.requests[1][:provider_options][:prediction]).to eq(expected)
    end
  end

  context "when the transcript holds system messages" do
    let(:behavior) { ->(_chat, _n) { final_message("ok") } }

    it "sends each one exactly once, translating structured content" do
      probe.transcript << { system: "You are terse" }
      probe.transcript << { system: [{ type: "text", text: "Answer in haiku", cache_control: { type: "ephemeral" } }] }

      probe.chat_completion(available_tools: false)

      expect(fake_chat.instructions).to eq(["You are terse", "Answer in haiku"])
    end
  end

  context "when a tool calls stop_tool_calls_and_respond!" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:finish_now) : final_message("final answer after stop")
      end
    end

    it "stops the loop and forces a final text response" do
      response = probe.chat_completion(max_tool_calls: 25)

      expect(response).to eq("final answer after stop")
      # The function itself ran (unlike a cap refusal), then the loop stopped.
      expect(probe.finish_executions).to eq(1)
      expect(fake_chat.generate_count).to eq(2)
    end

    it "does not inject the max-tool-calls limit message" do
      probe.chat_completion(max_tool_calls: 25)

      expect(fake_chat.instructions).not_to include(a_string_matching(/Maximum tool calls/))
    end

    context "and the same instance is used again afterwards" do
      let(:behavior) do
        lambda do |_chat, n|
          case n
          when 1 then tool_call_message(:finish_now)
          when 2 then final_message("final answer after stop")
          when 3 then tool_call_message(:do_work)
          else final_message("second answer")
          end
        end
      end

      it "does not carry the earlier stop request into the later call" do
        probe.chat_completion(max_tool_calls: 25)
        response = probe.chat_completion(max_tool_calls: 25)

        expect(response).to eq("second answer")
        expect(probe.work_executions).to eq(1)
        # The second call's follow-up round is an ordinary continuation with
        # tools registered, not a forced tool-less final.
        expect(fake_chat.requests.last[:tools_registered]).to eq(2)
      end
    end
  end

  context "when max_tool_calls is 0" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work) : final_message("final answer with no budget")
      end
    end

    it "refuses every tool call and forces the final response on the first round" do
      response = probe.chat_completion(max_tool_calls: 0)

      expect(response).to eq("final answer with no budget")
      expect(probe.work_executions).to eq(0)
      expect(fake_chat.generate_count).to eq(2)
      expect(fake_chat.instructions).to include(a_string_matching(/Maximum tool calls \(0\) exceeded/))
    end
  end

  context "when tool use stays under budget" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work, count: 2) : final_message("done under budget")
      end
    end

    it "runs every tool call and returns the model's own text" do
      response = probe.chat_completion(max_tool_calls: 5)

      expect(response).to eq("done under budget")
      expect(probe.work_executions).to eq(2)
      expect(fake_chat.generate_count).to eq(2)
      expect(fake_chat.instructions).not_to include(a_string_matching(/Maximum tool calls/))
    end
  end

  context "when no tools are involved" do
    let(:behavior) { ->(_chat, _n) { final_message("plain text answer") } }

    it "returns the completion untouched" do
      response = probe.chat_completion(available_tools: false)

      expect(response).to eq("plain text answer")
      expect(fake_chat.tools).to be_empty
      expect(fake_chat.generate_count).to eq(1)
    end
  end

  # Regression for the Codex finding: when chat_completion is driven by the
  # documented `messages:` argument, those messages never enter the transcript.
  # Every follow-up request — including the forced final one — must still carry
  # the caller's system/user prompt, not just the tool exchange.
  context "when driven by an explicit messages: argument and the budget runs out" do
    subject(:probe) { ExplicitMessagesProbe.new }

    let(:messages) do
      [{ system: "You are a helpful assistant" }, { user: "Do some work then summarize" }]
    end

    let(:behavior) do
      lambda do |_chat, n|
        n <= 2 ? tool_call_message(:do_work) : final_message("final answer from explicit messages")
      end
    end

    it "replays the caller-provided system and user messages into the forced final completion" do
      response = probe.chat_completion(messages:, max_tool_calls: 1)

      expect(response).to eq("final answer from explicit messages")
      expect(probe.work_executions).to eq(1)

      final_request = fake_chat.requests.last
      # The original system prompt survives into the tool-less final request...
      expect(final_request[:instructions]).to include("You are a helpful assistant")
      # ...as does the original user message (not just the tool exchange).
      user_contents = final_request[:messages].select { |m| m[:role] == :user }.map { |m| m[:content] }
      expect(user_contents).to include("Do some work then summarize")
      # And the tool result still rides along so the model can use it.
      tool_contents = final_request[:messages].select { |m| m[:role] == :tool }.map { |m| m[:content] }
      expect(tool_contents).to include("work result 1")
    end
  end

  context "when the caller forces tool_choice" do
    let(:behavior) do
      lambda do |_chat, n|
        n == 1 ? tool_call_message(:do_work) : final_message("answer after the forced call")
      end
    end

    it "sends the forced tool_choice on the first round only, so the model can answer afterwards" do
      response = probe.chat_completion(params: { tool_choice: "required" }, max_tool_calls: 5)

      expect(response).to eq("answer after the forced call")
      expect(probe.work_executions).to eq(1)
      expect(fake_chat.requests.first[:provider_options]).to include(tool_choice: "required")
      expect(fake_chat.requests.last[:provider_options]).not_to have_key(:tool_choice)
    end

    it "leaves the caller's params Hash untouched" do
      params = { tool_choice: "required" }

      probe.chat_completion(params:, max_tool_calls: 5)

      expect(params).to eq(tool_choice: "required")
    end

    it "does not re-apply an instance-level tool_choice on continuation rounds" do
      probe.tool_choice = "required"
      probe.chat_completion(max_tool_calls: 5)

      expect(fake_chat.requests.first[:provider_options]).to include(tool_choice: "required")
      expect(fake_chat.requests.last[:provider_options]).not_to have_key(:tool_choice)
    end
  end

  context "when available_tools restricts the toolset" do
    let(:behavior) { ->(_chat, _n) { final_message("restricted") } }

    it "registers only the named functions with the chat" do
      probe.chat_completion(available_tools: [:do_work])

      expect(fake_chat.tools.keys).to eq([:do_work])
    end

    it "registers every declared function when available_tools is not given" do
      probe.chat_completion

      expect(fake_chat.tools.keys).to contain_exactly(:do_work, :finish_now)
    end

    it "still resolves tool names when a before_completion hook hands back string-keyed tools" do
      probe.before_completion = ->(context) { { tools: JSON.parse(context.params[:tools].to_json) } }

      probe.chat_completion(available_tools: [:do_work])

      expect(fake_chat.tools.keys).to eq([:do_work])
    end

    context "when a hook offers a tool name the class never declared" do
      let(:behavior) do
        lambda do |_chat, n|
          n == 1 ? tool_call_message(:instance_variable_set) : final_message("declined politely")
        end
      end

      it "refuses to dispatch it even though it was in params[:tools], and tells the model so" do
        probe.before_completion = lambda do |context|
          { tools: context.params[:tools] + [{ type: "function", function: { name: "instance_variable_set" } }] }
        end

        response = probe.chat_completion

        expect(response).to eq("declined politely")
        expect(tool_contents(fake_chat.requests[1])).to eq(["Tool call refused: instance_variable_set is not available on this request."])
      end
    end

    context "when the model calls a declared function that available_tools excluded" do
      let(:behavior) do
        lambda do |_chat, n|
          n == 1 ? tool_call_message(:finish_now) : final_message("declined politely")
        end
      end

      it "refuses to dispatch it and lets the model continue" do
        response = probe.chat_completion(available_tools: [:do_work])

        expect(response).to eq("declined politely")
        expect(probe.finish_executions).to eq(0)
        expect(tool_contents(fake_chat.requests[1])).to eq(["Tool call refused: finish_now is not available on this request."])
      end
    end
  end

  context "when a tool body calls chat_completion on the same instance" do
    subject(:probe) { NestingProbe.new }

    # generate 1: outer round asks for :delegate. Inside it, generate 2 is the
    # nested loop's first round (asks for :do_work) and generate 3 its answer.
    # generate 4 resumes the outer loop with another :do_work; generate 5 ends it.
    let(:behavior) do
      lambda do |_chat, n|
        case n
        when 1 then tool_call_message(:delegate)
        when 2, 4 then tool_call_message(:do_work)
        when 3 then final_message("inner done")
        else final_message("outer done")
        end
      end
    end

    it "keeps the outer loop's budget and lets the nested call use its own settings" do
      response = probe.chat_completion(max_tool_calls: 3)

      expect(response).to eq("outer done")
      expect(probe.inner_result).to eq("inner done")
      expect(probe.work_executions).to eq(2)
      expect(fake_chat.generate_count).to eq(5)
      # Outer budget of 3 (delegate + do_work) was never exhausted by the nested call's budget of 1.
      expect(fake_chat.instructions).not_to include(a_string_matching(/Maximum tool calls/))
      # The nested call's own forced tool_choice is honored on its first round
      # even though the outer loop is mid-flight, and dropped on its second.
      expect(fake_chat.requests[1][:provider_options]).to include(tool_choice: "required")
      expect(fake_chat.requests[2][:provider_options]).not_to have_key(:tool_choice)
      # The outer request carries the delegate's return value and the outer
      # loop's own do_work result, but nothing the nested loop did internally.
      outer_results = tool_contents(fake_chat.requests.last)
      expect(outer_results).to include("delegated", "work result 2")
      expect(outer_results).not_to include("work result 1")
      # The nested call ran with save_response: false, so its rounds stay out
      # of the transcript and cannot surface in a later top-level call either.
      recorded = probe.transcript.flatten.select { |m| m[:role] == "tool" }.map { |m| m[:content] }
      expect(recorded).to eq(["delegated", "work result 2"])
    end

    context "and a tool in a continuation round raises JSON::ParserError" do
      let(:behavior) do
        lambda do |_chat, n|
          case n
          when 1 then tool_call_message(:do_work)
          when 2 then tool_call_message(:bad_json)
          else final_message("unreachable")
          end
        end
      end

      it "propagates through the outer frame without a retry" do
        expect { probe.chat_completion(max_tool_calls: 5) }.to raise_error(JSON::ParserError)

        expect(fake_chat.generate_count).to eq(2)
        expect(probe.work_executions).to eq(1)
      end
    end

    context "and the tool raises" do
      let(:behavior) do
        lambda do |_chat, n|
          case n
          when 1 then tool_call_message(:boom)
          when 2 then tool_call_message(:do_work)
          else final_message("recovered")
          end
        end
      end

      it "propagates the error and leaves the instance ready for a fresh call" do
        expect { probe.chat_completion(max_tool_calls: 3) }.to raise_error(RuntimeError, "boom")
        expect(probe.max_tool_calls).to eq(3)

        response = probe.chat_completion(params: { tool_choice: "required" }, max_tool_calls: 3)

        expect(response).to eq("recovered")
        expect(probe.work_executions).to eq(1)
        # Depth bookkeeping unwound, so the fresh call's forced tool_choice is
        # honored on its first round.
        expect(fake_chat.requests[1][:provider_options]).to include(tool_choice: "required")
        expect(fake_chat.instructions).not_to include(a_string_matching(/Maximum tool calls/))
      end
    end

    context "and a tool inside the nested loop requests a stop" do
      let(:behavior) do
        lambda do |_chat, n|
          case n
          when 1 then tool_call_message(:delegate_to_stopper)
          when 2 then tool_call_message(:finish_now)
          when 3 then final_message("inner stopped")
          when 4 then tool_call_message(:do_work)
          else final_message("outer done")
          end
        end
      end

      it "stops only the nested loop, and the outer loop keeps calling tools" do
        response = probe.chat_completion(max_tool_calls: 5)

        expect(response).to eq("outer done")
        # Outer round 2 still ran do_work; a leaked stop would have forced the
        # final answer at generate 4 with no tool executed.
        expect(probe.work_executions).to eq(1)
        expect(fake_chat.generate_count).to eq(5)
      end
    end

    context "and a later tool in the batch raises" do
      let(:behavior) do
        lambda do |_chat, n|
          n == 1 ? mixed_tool_call_message(:do_work, :boom, :do_work) : final_message("unreachable")
        end
      end

      it "records the completed results, the failure, and the unexecuted calls before re-raising" do
        expect { probe.chat_completion(max_tool_calls: 5) }.to raise_error(RuntimeError, "boom")

        expect(probe.work_executions).to eq(1)
        recorded = probe.transcript.flatten
        assistant = recorded.find { |m| m[:role] == "assistant" && m[:tool_calls] }
        expect(assistant[:tool_calls].map { |tc| tc["id"] }).to eq(%w[call_do_work_0 call_boom_1 call_do_work_2])
        results = recorded.select { |m| m[:role] == "tool" }
        expect(results.map { |m| [m[:tool_call_id], m[:content]] }).to eq(
          [
            ["call_do_work_0", "work result 1"],
            ["call_boom_1", "Tool call failed (RuntimeError)."],
            ["call_do_work_2", "Not executed: an earlier tool call in this batch failed."]
          ]
        )
      end
    end

    context "and a tool raises JSON::ParserError itself" do
      let(:behavior) do
        lambda do |_chat, n|
          n == 1 ? mixed_tool_call_message(:do_work, :bad_json) : final_message("unreachable")
        end
      end

      it "propagates the error without retrying the request or exposing the message" do
        expect { probe.chat_completion(max_tool_calls: 5) }.to raise_error(JSON::ParserError)

        # One request, one execution: the blank-JSON retry did not fire.
        expect(fake_chat.generate_count).to eq(1)
        expect(probe.work_executions).to eq(1)
        recorded = probe.transcript.flatten.select { |m| m[:role] == "tool" }.map { |m| m[:content] }
        expect(recorded).to eq(["work result 1", "Tool call failed (JSON::ParserError)."])
        expect(recorded.join).not_to include("SECRET")
      end
    end

    context "and the tool requests a stop after the nested call returns" do
      let(:behavior) do
        lambda do |_chat, n|
          case n
          when 1 then tool_call_message(:delegate_then_stop)
          when 2 then tool_call_message(:do_work)
          when 3 then final_message("inner done")
          else final_message("outer stopped")
          end
        end
      end

      it "stops the outer loop with one forced final" do
        response = probe.chat_completion(max_tool_calls: 5)

        expect(response).to eq("outer stopped")
        expect(probe.work_executions).to eq(1)
        expect(fake_chat.generate_count).to eq(4)
        expect(fake_chat.requests.last[:tools_registered]).to eq(0)
      end
    end

    context "and the nested loop ends by exhausting its own budget" do
      let(:behavior) do
        lambda do |_chat, n|
          case n
          when 1 then tool_call_message(:delegate_to_capped)
          when 2, 3, 5 then tool_call_message(:do_work)
          when 4 then final_message("inner capped")
          else final_message("outer done")
          end
        end
      end

      it "leaves the outer loop's budget untouched" do
        response = probe.chat_completion(max_tool_calls: 3)

        expect(response).to eq("outer done")
        expect(probe.inner_result).to eq("inner capped")
        # Nested: one do_work ran, the second was refused by its budget of 1.
        # Outer: delegate + one do_work = 2 of 3, so it never hit its own cap.
        expect(probe.work_executions).to eq(2)
        expect(fake_chat.generate_count).to eq(6)
        cap_messages = fake_chat.instructions.grep(/Maximum tool calls/)
        expect(cap_messages).to eq(["Maximum tool calls (1) exceeded. Please provide a final response to the user without calling any more tools."])
      end
    end

    context "and the nested call raises after the tool requested a stop" do
      let(:behavior) do
        lambda do |_chat, n|
          case n
          when 1 then tool_call_message(:stop_then_delegate_to_boom)
          when 2 then tool_call_message(:boom)
          when 3 then tool_call_message(:do_work)
          else final_message("recovered")
          end
        end
      end

      it "propagates the error and unwinds so a later call runs normally" do
        expect { probe.chat_completion(max_tool_calls: 5) }.to raise_error(RuntimeError, "boom")
        expect(probe.max_tool_calls).to eq(5)

        response = probe.chat_completion(max_tool_calls: 5)

        expect(response).to eq("recovered")
        expect(probe.work_executions).to eq(1)
        # The later call's follow-up round is an ordinary continuation, not a
        # forced final: the earlier stop did not leak into it.
        expect(fake_chat.requests.last[:tools_registered]).to be > 0
      end
    end

    context "and the tool requested a stop before nesting" do
      let(:behavior) do
        lambda do |_chat, n|
          case n
          when 1 then tool_call_message(:stop_then_delegate)
          when 2 then tool_call_message(:do_work)
          when 3 then final_message("inner done")
          else final_message("outer stopped")
          end
        end
      end

      it "still honors the outer stop after the nested loop resets the flag" do
        response = probe.chat_completion(max_tool_calls: 5)

        expect(response).to eq("outer stopped")
        # 3 nested/outer rounds plus exactly one forced final; no further tool rounds.
        expect(fake_chat.generate_count).to eq(4)
        expect(fake_chat.instructions).not_to include(a_string_matching(/Maximum tool calls/))
      end
    end
  end

  context "when replaying multiple system messages via messages:" do
    subject(:probe) { ExplicitMessagesProbe.new }

    let(:messages) do
      [{ system: "You are a helpful assistant" }, { system: "Always answer in haiku" }, { user: "Do some work" }]
    end

    let(:behavior) { ->(_chat, _n) { final_message("done") } }

    it "appends each system message onto the chat's instructions in order" do
      probe.chat_completion(messages:, max_tool_calls: 5)

      expect(fake_chat.instructions).to eq(["You are a helpful assistant", "Always answer in haiku"])
    end
  end
end
