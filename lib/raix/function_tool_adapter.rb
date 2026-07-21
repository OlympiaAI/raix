# frozen_string_literal: true

module Raix
  # Adapter to convert Raix function declarations to RubyLLM::Tool instances
  class FunctionToolAdapter
    # Sentinels wrapped in a RubyLLM::Tool::Halt so that ChatCompletion can tell
    # *why* RubyLLM's internal tool loop was halted from inside a generated tool
    # wrapper. Internal API — not intended for use outside Raix.
    ToolCallsCapReached = Struct.new(:max_tool_calls)
    StopToolCallsRequested = Struct.new(:result)

    def self.create_tool_from_function(function_def, instance)
      tool_class = Class.new(RubyLLM::Tool) do
        description function_def[:description] if function_def[:description]

        # Forward the full JSON-schema parameter dict to RubyLLM rather than
        # rebuilding it field-by-field via `param(...)`. The per-field path
        # only carried `type` and `description`, which silently dropped richer
        # schema like `additionalProperties`, `items`, `enum`, or nested
        # `properties` — leaving providers (notably Gemini's structured output)
        # to invent degenerate shapes for `type: object` arguments.
        if function_def[:parameters].is_a?(Hash) && function_def[:parameters][:properties].present?
          # RubyLLM's `params(schema)` path forwards the schema verbatim and, unlike the
          # per-field `param(...)` path, does not inject the OpenAI strict-mode guards. Default
          # them on so existing tools keep strict behavior, while letting a function declaration
          # override either by setting it explicitly.
          params({ additionalProperties: false, strict: true }.merge(function_def[:parameters]))
        end

        # Store reference to the instance and function name
        define_method(:raix_instance) { instance }
        define_method(:raix_function_name) { function_def[:name] }

        # Override execute to call the Raix function.
        #
        # The max_tool_calls budget is enforced here, inside the generated
        # wrapper, because RubyLLM drives the tool loop internally
        # (complete -> handle_tool_calls -> complete) and never yields control
        # back to Raix between rounds. Counting must therefore happen per tool
        # invocation: a single model response can pack several parallel tool
        # calls, all of which RubyLLM executes in one round even after one has
        # halted, so each wrapper checks the shared counter independently.
        define_method(:execute) do |**args|
          if raix_instance.increment_tool_call_count > raix_instance.max_tool_calls
            # Refuse to run the underlying function and halt the loop. RubyLLM
            # returns this Halt from chat.complete; ChatCompletion turns it into
            # a final, tool-less completion.
            halt(ToolCallsCapReached.new(raix_instance.max_tool_calls))
          else
            result = raix_instance.public_send(raix_function_name, args.with_indifferent_access, nil)

            # stop_tool_calls_and_respond! sets a flag that only the old (now
            # unreachable) counting loop used to read. Honor it here so it still
            # forces a final text response under the RubyLLM backend.
            if raix_instance.stop_tool_calls_and_respond
              halt(StopToolCallsRequested.new(result))
            else
              result
            end
          end
        end
      end

      # Set a meaningful name for the tool class
      tool_class.define_singleton_method(:name) do
        "Raix::GeneratedTool::#{function_def[:name].to_s.camelize}"
      end

      tool_instance = tool_class.new

      # Override the name method to return the original function name
      # This ensures RubyLLM can match the tool call from the AI
      tool_instance.define_singleton_method(:name) do
        function_def[:name].to_s
      end

      tool_instance
    end

    def self.convert_tools_for_ruby_llm(raix_instance)
      return [] unless raix_instance.class.respond_to?(:functions)
      return [] if raix_instance.class.functions.blank?

      raix_instance.class.functions.map do |function_def|
        create_tool_from_function(function_def, raix_instance)
      end
    end
  end
end
