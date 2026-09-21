# frozen_string_literal: true

module Raix
  # Adapter to convert Raix function declarations to RubyLLM::Tool instances.
  #
  # The generated tools exist so RubyLLM sends the right schema to the
  # provider. Raix drives the tool loop itself (see ChatCompletion), so it
  # dispatches functions through `dispatch_tool_function` rather than letting
  # RubyLLM execute these wrappers. `execute` is still implemented correctly so
  # a generated tool behaves sanely if invoked directly.
  class FunctionToolAdapter
    def self.create_tool_from_function(function_def, instance)
      tool_class = Class.new(RubyLLM::Tool) do
        description function_def[:description] if function_def[:description]

        # Forward the full JSON-schema parameter dict to RubyLLM rather than
        # rebuilding it field-by-field via `parameter(...)`. The per-field path
        # only carries `type` and `description`, which silently drops richer
        # schema like `additionalProperties`, `items`, `enum`, or nested
        # `properties` — leaving providers (notably Gemini's structured output)
        # to invent degenerate shapes for `type: object` arguments.
        if function_def[:parameters].is_a?(Hash) && function_def[:parameters][:properties].present?
          # RubyLLM's `parameters(schema)` path forwards the schema verbatim and, unlike the
          # per-field `parameter(...)` path, does not inject the OpenAI strict-mode guards. Default
          # them on so existing tools keep strict behavior, while letting a function declaration
          # override either by setting it explicitly.
          parameters({ additionalProperties: false, strict: true }.merge(function_def[:parameters]))
        end

        # Store reference to the instance and function name
        define_method(:raix_instance) { instance }
        define_method(:raix_function_name) { function_def[:name] }

        define_method(:execute) do |**args|
          raix_instance.public_send(raix_function_name, args.with_indifferent_access, nil)
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

    # Converts the instance's declared functions. Pass `only:` (an array of
    # function names) to convert just that subset, which is how
    # `available_tools` restricts what the model can see.
    def self.convert_tools_for_ruby_llm(raix_instance, only: nil)
      return [] unless raix_instance.class.respond_to?(:functions)

      functions = Array(raix_instance.class.functions)
      functions = functions.select { |function_def| only.include?(function_def[:name].to_s) } if only

      functions.map do |function_def|
        create_tool_from_function(function_def, raix_instance)
      end
    end
  end
end
