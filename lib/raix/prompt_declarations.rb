# frozen_string_literal: true

require "ostruct"
require "active_support/core_ext/string/filters"

module Raix
  # The PromptDeclarations module provides a way to chain prompts and handle
  # user responses in a serialized manner (in the order they were defined),
  # with support for functions if the FunctionDispatch module is also included.
  module PromptDeclarations
    extend ActiveSupport::Concern
    extend ChatCompletion

    module ClassMethods # rubocop:disable Style/Documentation
      # Adds a prompt to the list of prompts.
      #
      # @param system [Proc] A lambda that generates the system message.
      # @param text [Proc] A lambda that generates the prompt text. (Required)
      # @param success [Proc] The block of code to execute when the prompt is answered.
      # @param parameters [Hash] Additional parameters for the completion API call
      # @param stream [Boolean] Whether to stream the response.
      def prompt(text:, system: nil, success: nil, params: {}, stream: false)
        name = Digest::SHA256.hexdigest(text.inspect)[0..7]
        prompts << begin
          OpenStruct.new({ name:, system:, text:, success:, params:, stream: })
        end

        define_method(name) do |response|
          if Rails.env.local?
            puts "_" * 80
            puts "PromptDeclarations#response:"
            puts "#{text.source_location} (#{name})"
            puts response
            puts "_" * 80
          end

          return response if success.nil?
          return send(success, response) if success.is_a?(Symbol)

          instance_exec(response, &success)
        end
      end

      # the list of prompts declared at class level
      def prompts
        @prompts ||= []
      end

      # getter/setter for system prompt declared at class level
      def system_prompt(prompt = nil)
        prompt ? @system_prompt = prompt.squish : @system_prompt
      end
    end

    # Executes the chat completion process based on the class-level declared prompts.
    # The response to each prompt is added to the transcript automatically and returned.
    #
    # Prompts require at least a `text` lambda parameter.
    #
    # @param params [Hash] Parameters for the chat completion override those defined in the current prompt.
    # @option params [Boolean] :raw (false) Whether to return the raw response or dig the text content.
    #
    # Uses system prompt in following order of priority:
    #   - system lambda specified in the prompt declaration
    #   - system_prompt instance method if defined
    #   - system_prompt class-level declaration if defined
    #
    #  TODO: shortcut syntax passes just a string prompt if no other options are needed.
    #
    # @raise [RuntimeError] If no prompts are defined.
    #
    def chat_completion(params: {}, raw: false)
      raise "No prompts defined" unless self.class.prompts.present?

      current_prompts = self.class.prompts.clone

      while (@current_prompt = current_prompts.shift)
        __system_prompt = instance_exec(&@current_prompt.system) if @current_prompt.system.present? # rubocop:disable Lint/UnderscorePrefixedVariableName
        __system_prompt ||= system_prompt if respond_to?(:system_prompt)
        __system_prompt ||= self.class.system_prompt.presence
        transcript << { system: __system_prompt } if __system_prompt
        transcript << { user: instance_exec(&@current_prompt.text) } # text is required

        params = @current_prompt.params.merge(params)

        # set the stream if necessary
        self.stream = instance_exec(&@current_prompt.stream) if @current_prompt.stream.present?

        super(params:, raw:).then do |response|
          transcript << { assistant: response }
          @last_response = send(@current_prompt.name, response)
        end
      end

      @last_response
    end

    # Returns the model parameter of the current prompt or the default model.
    #
    # @return [Object] The model parameter of the current prompt or the default model.
    def model
      @current_prompt.params[:model] || super
    end

    # Returns the temperature parameter of the current prompt or the default temperature.
    #
    # @return [Float] The temperature parameter of the current prompt or the default temperature.
    def temperature
      @current_prompt.params[:temperature] || super
    end

    # Returns the max_tokens parameter of the current prompt or the default max_tokens.
    #
    # @return [Integer] The max_tokens parameter of the current prompt or the default max_tokens.
    def max_tokens
      @current_prompt.params[:max_tokens] || super
    end
  end
end
