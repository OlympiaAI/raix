# frozen_string_literal: true

require "securerandom"
module Raix
  # Provides declarative function definition for ChatCompletion classes.
  #
  # Example:
  #
  #   class MeaningOfLife
  #     include Raix::ChatCompletion
  #     include Raix::FunctionDispatch
  #
  #     function :ask_deep_thought do
  #       wait 236_682_000_000_000
  #       "The meaning of life is 42"
  #     end
  #
  #     def initialize
  #       transcript << { user: "What is the meaning of life?" }
  #       chat_completion
  #     end
  #   end
  module FunctionDispatch
    extend ActiveSupport::Concern

    class_methods do
      attr_reader :functions

      # Defines a function that can be dispatched by the ChatCompletion module while
      # processing the response from an AI model.
      #
      # Declaring a function here will automatically add it (in JSON Schema format) to
      # the list of tools provided to the OpenRouter Chat Completion API. The function
      # will be dispatched by name, so make sure the name is unique. The function's block
      # argument will be executed in the instance context of the class that includes this module.
      #
      # Example:
      #   function :google_search, "Search Google for something", query: { type: "string" } do |arguments|
      #     GoogleSearch.new(arguments[:query]).search
      #   end
      #
      # @param name [Symbol] The name of the function.
      # @param description [String] An optional description of the function.
      # @param parameters [Hash] The parameters that the function accepts.
      # @param block [Proc] The block of code to execute when the function is called.
      def function(name, description = nil, **parameters, &block)
        @functions ||= []
        @functions << begin
          { name:, parameters: { type: "object", properties: {} } }.tap do |definition|
            definition[:description] = description if description.present?
            parameters.map do |key, value|
              definition[:parameters][:properties][key] = value
            end
          end
        end

        define_method(name) do |arguments|
          id = SecureRandom.uuid[0, 23]
          transcript << {
            role: "assistant",
            content: nil,
            tool_calls: [
              {
                id:,
                type: "function",
                function: {
                  name:,
                  arguments: arguments.to_json
                }
              }
            ]
          }
          instance_exec(arguments, &block).tap do |content|
            transcript << {
              role: "tool",
              tool_call_id: id,
              name:,
              content: content.to_s
            }
            # TODO: add on_error handler as optional parameter to function
          end

          chat_completion(**chat_completion_args) if loop
        end
      end
    end

    included do
      attr_accessor :chat_completion_args
    end

    def chat_completion(**chat_completion_args)
      raise "No functions defined" if self.class.functions.blank?

      self.chat_completion_args = chat_completion_args

      super
    end

    # Stops the looping of chat completion after function calls.
    # Useful for manually halting processing in workflow components
    # that do not require a final text response to an end user.
    def stop_looping!
      self.loop = false
    end

    def tools
      self.class.functions.map { |function| { type: "function", function: } }
    end
  end
end
