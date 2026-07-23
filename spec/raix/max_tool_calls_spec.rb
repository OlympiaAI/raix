# frozen_string_literal: true

# Regression coverage for max_tool_calls enforcement under the RubyLLM backend.
#
# RubyLLM drives the whole tool-call loop internally (complete ->
# handle_tool_calls -> complete) and only returns once the model stops calling
# tools. The counting loop in ChatCompletion therefore never saw a tool round,
# so `max_tool_calls` and `stop_tool_calls_and_respond!` were both dead. The fix
# enforces the budget inside the generated FunctionToolAdapter wrapper, which
# returns a RubyLLM::Tool::Halt to stop the loop; ChatCompletion then forces one
# final completion without tools.

# A fake RubyLLM::Chat that records what Raix does to it and lets each spec
# script what `complete` returns. The same instance is handed back for every
# `RubyLLM.chat` call (transcript memo + each request), matching how the real
# backend reuses one conversation. `complete`/`ask` invoke the provided behavior
# with the chat and the 1-based completion number so a spec can run tools on the
# first pass and return a final message on the forced second pass.
class ScriptedRubyLLMChat
  attr_reader :instructions, :tools, :with_tool_count, :complete_count, :tool_count_at_complete, :requests

  def initialize(&behavior)
    @behavior = behavior
    @instructions = []
    @tools = {}
    @with_tool_count = 0
    @complete_count = 0
    @tool_count_at_complete = []
    # Per-completion capture: each entry records the instructions and messages
    # applied to this chat since the previous completion, so a spec can inspect
    # exactly what the forced final (tool-less) request was rebuilt from.
    @requests = []
    @current_instructions = []
    @current_messages = []
  end

  def with_instructions(content, **)
    @instructions << content
    @current_instructions << content
    self
  end

  def add_message(**attrs)
    @current_messages << attrs
    self
  end

  def reset_messages!; end
  def messages = []
  def with_temperature(_) = self
  def with_params(**) = self

  def with_tool(tool)
    @with_tool_count += 1
    @tools[tool.name.to_sym] = tool
    self
  end

  def ask(&) = complete(&)

  def complete(&)
    @complete_count += 1
    @tool_count_at_complete << @with_tool_count
    result = @behavior.call(self, @complete_count)
    @requests << { instructions: @current_instructions.dup, messages: @current_messages.dup }
    @current_instructions = []
    @current_messages = []
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

RSpec.describe Raix::ChatCompletion, "max_tool_calls enforcement under RubyLLM" do
  subject(:probe) { ToolBudgetProbe.new }

  def final_message(content)
    instance_double(
      "RubyLLM::Message",
      content:,
      tool_calls: nil,
      tool_call?: false,
      input_tokens: 5,
      output_tokens: 5,
      model_id: "test-model",
      raw: nil
    )
  end

  # Simulate a round in which the model issues `count` calls to `tool_name`,
  # exactly as RubyLLM's handle_tool_calls does: every call runs even after one
  # halts, and the halt (if any) is what the loop returns.
  def run_round(chat, tool_name, count)
    halt = nil
    count.times do |i|
      result = chat.tools[tool_name].call({ n: i })
      halt ||= result if result.is_a?(RubyLLM::Tool::Halt)
    end
    halt
  end

  let(:fake_chat) { ScriptedRubyLLMChat.new(&behavior) }

  before { allow(RubyLLM).to receive(:chat).and_return(fake_chat) }

  context "when the model keeps calling tools past the budget" do
    # One call per round; the loop runs until the wrapper halts.
    let(:behavior) do
      lambda do |chat, n|
        if n == 1
          halt = nil
          10.times do
            result = chat.tools[:do_work].call({ n: 1 })
            if result.is_a?(RubyLLM::Tool::Halt)
              halt = result
              break
            end
          end
          halt || raise("expected the wrapper to halt but it never did")
        else
          final_message("final answer after cap")
        end
      end
    end

    it "refuses the tool call that exceeds max_tool_calls and returns a forced final response" do
      response = probe.chat_completion(max_tool_calls: 2)

      expect(response).to eq("final answer after cap")
      # do_work ran exactly twice (calls 1 and 2); the 3rd was refused.
      expect(probe.work_executions).to eq(2)
    end

    it "issues the final completion without tools and injects the limit system message" do
      probe.chat_completion(max_tool_calls: 2)

      expect(fake_chat.complete_count).to eq(2)
      # 2 tools registered before the first completion, 0 more before the forced
      # final one -> the final pass carries no tools.
      expect(fake_chat.tool_count_at_complete).to eq([2, 2])
      expect(fake_chat.instructions).to include(a_string_matching(/Maximum tool calls \(2\) exceeded/))
    end
  end

  context "when a single response packs several parallel tool calls" do
    # All calls happen in one round, mirroring parallel tool calls in one model
    # response.
    let(:behavior) do
      lambda do |chat, n|
        n == 1 ? run_round(chat, :do_work, 5) : final_message("final answer parallel")
      end
    end

    it "enforces the cap per call so the round cannot blow past it" do
      response = probe.chat_completion(max_tool_calls: 2)

      expect(response).to eq("final answer parallel")
      # Only the first 2 of the 5 parallel calls ran; the rest were refused.
      expect(probe.work_executions).to eq(2)
    end
  end

  context "when a tool calls stop_tool_calls_and_respond!" do
    let(:behavior) do
      lambda do |chat, n|
        if n == 1
          chat.tools[:finish_now].call({})
        else
          final_message("final answer after stop")
        end
      end
    end

    it "halts the loop and forces a final text response" do
      response = probe.chat_completion(max_tool_calls: 25)

      expect(response).to eq("final answer after stop")
      # The function itself ran (unlike a cap refusal), then the loop stopped.
      expect(probe.finish_executions).to eq(1)
      expect(fake_chat.complete_count).to eq(2)
      expect(fake_chat.tool_count_at_complete).to eq([2, 2])
    end

    it "does not inject the max-tool-calls limit message" do
      probe.chat_completion(max_tool_calls: 25)

      expect(fake_chat.instructions).not_to include(a_string_matching(/Maximum tool calls/))
    end
  end

  context "regression: chat.complete returns a bare Halt" do
    # Isolates the crash path (Halt has no #raw / #input_tokens) from the tool
    # mechanics: the first completion returns a Halt directly.
    let(:behavior) do
      lambda do |_chat, n|
        if n == 1
          RubyLLM::Tool::Halt.new(Raix::FunctionToolAdapter::ToolCallsCapReached.new(3))
        else
          final_message("recovered")
        end
      end
    end

    it "does not raise and returns the final response" do
      expect { @result = probe.chat_completion(max_tool_calls: 3) }.not_to raise_error
      expect(@result).to eq("recovered")
    end
  end

  context "when tool use stays under budget" do
    # Two rounds of one call each, then the model returns text on its own -> no
    # halt, normal Message path.
    let(:behavior) do
      lambda do |chat, n|
        if n == 1
          chat.tools[:do_work].call({ n: 1 })
          chat.tools[:do_work].call({ n: 2 })
          final_message("done under budget")
        else
          final_message("should not be reached")
        end
      end
    end

    it "runs every tool call and returns the model's own text without a second completion" do
      response = probe.chat_completion(max_tool_calls: 5)

      expect(response).to eq("done under budget")
      expect(probe.work_executions).to eq(2)
      expect(fake_chat.complete_count).to eq(1)
      expect(fake_chat.instructions).not_to include(a_string_matching(/Maximum tool calls/))
    end
  end

  context "when no tools are involved" do
    let(:behavior) { ->(_chat, _n) { final_message("plain text answer") } }

    it "returns the completion untouched" do
      response = probe.chat_completion(available_tools: false)

      expect(response).to eq("plain text answer")
      expect(fake_chat.with_tool_count).to eq(0)
      expect(fake_chat.complete_count).to eq(1)
    end
  end

  # Regression for the Codex finding: when chat_completion is driven by the
  # documented `messages:` argument, those messages never enter the transcript.
  # The forced final completion after a halt must still carry the caller's
  # system/user prompt, not just the tool exchange recorded in the transcript.
  context "when driven by an explicit messages: argument and a tool halts" do
    subject(:probe) { ExplicitMessagesProbe.new }

    let(:messages) do
      [{ system: "You are a helpful assistant" }, { user: "Do some work then summarize" }]
    end

    let(:behavior) do
      lambda do |chat, n|
        if n == 1
          halt = nil
          10.times do
            result = chat.tools[:do_work].call({ n: 1 })
            if result.is_a?(RubyLLM::Tool::Halt)
              halt = result
              break
            end
          end
          halt || raise("expected the wrapper to halt but it never did")
        else
          final_message("final answer from explicit messages")
        end
      end
    end

    it "replays the caller-provided system and user messages into the forced final completion" do
      response = probe.chat_completion(messages:, max_tool_calls: 1)

      expect(response).to eq("final answer from explicit messages")

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
end
