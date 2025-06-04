# frozen_string_literal: true

require "ostruct"

# This module provides a way to chain prompts and handle
# user responses in a serialized manner, with support for
# functions if the FunctionDispatch module is also included.
module PromptDeclarations
  extend ActiveSupport::Concern

  module ClassMethods # rubocop:disable Style/Documentation
    # Adds a prompt to the list of prompts. At minimum, provide a `text` or `call` parameter.
    #
    # @param system [Proc] A lambda that generates the system message.
    # @param call [ChatCompletion] A callable class that includes ChatCompletion. Will be passed a context object when initialized.
    # @param text Accepts 1) a lambda that returns the prompt text, 2) a string, or 3) a symbol that references a method.
    # @param stream [Proc] A lambda stream handler
    # @param success [Proc] The block of code to execute when the prompt is answered.
    # @param params [Hash] Additional parameters for the completion API call
    # @param if [Proc] A lambda that determines if the prompt should be executed.
    def prompt(system: nil, call: nil, text: nil, stream: nil, success: nil, params: {}, if: nil, unless: nil, until: nil)
      name = Digest::SHA256.hexdigest(text.inspect)[0..7]
      prompts << OpenStruct.new({ name:, system:, call:, text:, stream:, success:, if:, unless:, until:, params: })

      define_method(name) do |response|
        puts "_" * 80
        puts "PromptDeclarations#response:"
        puts "#{text&.source_location} (#{name})"
        puts response
        puts "_" * 80

        return response if success.nil?
        return send(success, response) if success.is_a?(Symbol)

        instance_exec(response, &success)
      end
    end

    def prompts
      @prompts ||= []
    end
  end

  attr_reader :current_prompt, :last_response

  MAX_LOOP_COUNT = 5

  # Executes the chat completion process based on the class-level declared prompts.
  # The response to each prompt is added to the transcript automatically and returned.
  #
  # Raises an error if there are not enough prompts defined.
  #
  # Uses system prompt in following order of priority:
  #   - system lambda specified in the prompt declaration
  #   - system_prompt instance method if defined
  #   - system_prompt class-level declaration if defined
  #
  #  Prompts require a text lambda to be defined at minimum.
  #  TODO: shortcut syntax passes just a string prompt if no other options are needed.
  #
  # @raise [RuntimeError] If no prompts are defined.
  #
  # @param prompt [String] The prompt to use for the chat completion.
  # @param params [Hash] Parameters for the chat completion.
  # @param raw [Boolean] Whether to return the raw response.
  #
  # TODO: SHOULD NOT HAVE A DIFFERENT INTERFACE THAN PARENT
  def chat_completion(prompt = nil, params: {}, raw: false, openai: false)
    raise "No prompts defined" unless self.class.prompts.present?

    loop_count = 0

    current_prompts = self.class.prompts.clone

    while (@current_prompt = current_prompts.shift)
      next if @current_prompt.if.present? && !instance_exec(&@current_prompt.if)
      next if @current_prompt.unless.present? && instance_exec(&@current_prompt.unless)

      input = case current_prompt.text
              when Proc
                instance_exec(&current_prompt.text)
              when String
                current_prompt.text
              when Symbol
                send(current_prompt.text)
              else
                last_response.presence || prompt
              end

      if current_prompt.call.present?
        Rails.logger.debug "Calling #{current_prompt.call} with input: #{input}"
        current_prompt.call.new(self).call(input).tap do |response|
          if response.present?
            transcript << { assistant: response }
            @last_response = send(current_prompt.name, response)
          end
        end
      else
        __system_prompt = instance_exec(&current_prompt.system) if current_prompt.system.present? # rubocop:disable Lint/UnderscorePrefixedVariableName
        __system_prompt ||= system_prompt if respond_to?(:system_prompt)
        __system_prompt ||= self.class.system_prompt.presence
        transcript << { system: __system_prompt } if __system_prompt
        transcript << { user: instance_exec(&current_prompt.text) } # text is required

        params = current_prompt.params.merge(params)

        # set the stream if necessary
        self.stream = instance_exec(&current_prompt.stream) if current_prompt.stream.present?

        execute_ai_request(params:, raw:, openai:, transcript:, loop_count:)
      end

      next unless current_prompt.until.present? && !instance_exec(&current_prompt.until)

      if loop_count >= MAX_LOOP_COUNT
        Honeybadger.notify(
          "Max loop count reached in chat_completion. Forcing return.",
          context: {
            current_prompts:,
            prompt:,
            usage_subject: usage_subject.inspect,
            last_response: Current.or_response
          }
        )

        return last_response
      else
        current_prompts.unshift(@current_prompt) # put it back at the front
        loop_count += 1
      end
    end

    last_response
  end

  def execute_ai_request(params:, raw:, openai:, transcript:, loop_count:)
    chat_completion_from_superclass(params:, raw:, openai:).then do |response|
      transcript << { assistant: response }
      @last_response = send(current_prompt.name, response)
      self.stream = nil # clear it again so it's not used for the next prompt
    end
  rescue Conversation::StreamError => e
    # Bubbles the error up the stack if no loops remain
    raise Faraday::ServerError.new(nil, { status: e.status, body: e.response }) if loop_count >= MAX_LOOP_COUNT

    sleep 1.second # Wait before continuing
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

  protected

  # workaround for super.chat_completion, which is not available in ruby
  def chat_completion_from_superclass(*, **kargs)
    method(:chat_completion).super_method.call(*, **kargs)
  end
end
