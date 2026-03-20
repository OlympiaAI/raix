# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/hash/indifferent_access"
require "ruby_llm"

module Raix
  class UndeclaredToolError < StandardError; end

  # The `ChatCompletion` module is a Rails concern that provides a way to interact
  # with the OpenRouter Chat Completion API via its client. The module includes a few
  # methods that allow you to build a transcript of messages and then send them to
  # the API for completion. The API will return a response that you can use however
  # you see fit.
  #
  # When the AI responds with tool function calls instead of a text message, this
  # module automatically:
  # 1. Executes the requested tool functions
  # 2. Adds the function results to the conversation transcript
  # 3. Sends the updated transcript back to the AI for another completion
  # 4. Repeats this process until the AI responds with a regular text message
  #
  # This automatic continuation ensures that tool calls are seamlessly integrated
  # into the conversation flow. The AI can use tool results to formulate its final
  # response to the user. You can limit the number of tool calls using the
  # `max_tool_calls` parameter to prevent excessive function invocations.
  #
  # Tool functions must be defined on the class that includes this module. The
  # `FunctionDispatch` module provides a Rails-like DSL for declaring these
  # functions at the class level, which is cleaner than implementing them as
  # instance methods.
  #
  # Note that some AI models can make multiple tool function calls in a single
  # response. When that happens, the module executes all requested functions
  # before continuing the conversation.
  module ChatCompletion
    extend ActiveSupport::Concern

    attr_accessor :before_completion, :cache_at, :frequency_penalty, :logit_bias, :logprobs, :loop, :min_p, :model,
                  :presence_penalty, :prediction, :repetition_penalty, :response_format, :stream, :temperature,
                  :max_completion_tokens, :max_tokens, :seed, :stop, :top_a, :top_k, :top_logprobs, :top_p, :tools,
                  :available_tools, :tool_choice, :provider, :max_tool_calls, :stop_tool_calls_and_respond

    class_methods do
      # Returns the current configuration of this class. Falls back to global configuration for unset values.
      def configuration
        @configuration ||= Configuration.new(fallback: Raix.configuration)
      end

      # Let's you configure the class-level configuration using a block.
      def configure
        yield(configuration)
      end
    end

    # Instance level access to the class-level configuration.
    def configuration
      self.class.configuration
    end

    # This method performs chat completion based on the provided transcript and parameters.
    #
    # @param params [Hash] The parameters for chat completion.
    # @option loop [Boolean] :loop (false) DEPRECATED - The system now automatically continues after tool calls.
    # @option params [Boolean] :json (false) Whether to return the parse the response as a JSON object. Will search for <json> tags in the response first, then fall back to the default JSON parsing of the entire response.
    # @option params [String] :openai (nil) If non-nil, use OpenAI with the model specified in this param.
    # @option params [Boolean] :raw (false) Whether to return the raw response or dig the text content.
    # @option params [Array] :messages (nil) An array of messages to use instead of the transcript.
    # @option tools [Array|false] :available_tools (nil) Tools to pass to the LLM. Ignored if nil (default). If false, no tools are passed. If an array, only declared tools in the array are passed.
    # @option max_tool_calls [Integer] :max_tool_calls Maximum number of tool calls before forcing a text response. Defaults to the configured value.
    # @return [String|Hash] The completed chat response.
    def chat_completion(params: {}, loop: false, json: false, raw: false, openai: nil, save_response: true, messages: nil, available_tools: nil, max_tool_calls: nil)
      # set params to default values if not provided
      params[:cache_at] ||= cache_at.presence
      params[:frequency_penalty] ||= frequency_penalty.presence
      params[:logit_bias] ||= logit_bias.presence
      params[:logprobs] ||= logprobs.presence
      params[:max_completion_tokens] ||= max_completion_tokens.presence || configuration.max_completion_tokens
      params[:max_tokens] ||= max_tokens.presence || configuration.max_tokens
      params[:min_p] ||= min_p.presence
      params[:prediction] = { type: "content", content: params[:prediction] || prediction } if params[:prediction] || prediction.present?
      params[:presence_penalty] ||= presence_penalty.presence
      params[:provider] ||= provider.presence
      params[:repetition_penalty] ||= repetition_penalty.presence
      params[:response_format] ||= response_format.presence
      params[:seed] ||= seed.presence
      params[:stop] ||= stop.presence
      params[:temperature] ||= temperature.presence || configuration.temperature
      params[:tool_choice] ||= tool_choice.presence
      params[:tools] = if available_tools == false
                         nil
                       elsif available_tools.is_a?(Array)
                         filtered_tools(available_tools)
                       else
                         tools.presence
                       end
      params[:top_a] ||= top_a.presence
      params[:top_k] ||= top_k.presence
      params[:top_logprobs] ||= top_logprobs.presence
      params[:top_p] ||= top_p.presence

      json = true if params[:response_format].is_a?(Raix::ResponseFormat)

      if json
        unless openai
          params[:provider] ||= {}
          params[:provider][:require_parameters] = true
        end
        if params[:response_format].blank?
          params[:response_format] ||= {}
          params[:response_format][:type] = "json_object"
        end
      end

      # Deprecation warning for loop parameter
      if loop
        warn "\n\nWARNING: The 'loop' parameter is DEPRECATED and will be ignored.\nChat completions now automatically continue after tool calls until the AI provides a text response.\nUse 'max_tool_calls' to limit the number of tool calls (default: #{configuration.max_tool_calls}).\n\n"
      end

      # Set max_tool_calls from parameter or configuration default
      self.max_tool_calls = max_tool_calls || configuration.max_tool_calls

      # Reset stop_tool_calls_and_respond flag
      @stop_tool_calls_and_respond = false

      # Track tool call count
      tool_call_count = 0

      # set the model to the default if not provided
      self.model ||= configuration.model

      adapter = MessageAdapters::Base.new(self)

      # duplicate the transcript to avoid race conditions in situations where
      # chat_completion is called multiple times in parallel
      # TODO: Defensive programming, ensure messages is an array
      messages ||= transcript.flatten.compact
      messages = messages.map { |msg| adapter.transform(msg) }.dup
      raise "Can't complete an empty transcript" if messages.blank?

      # Run before_completion hooks (global -> class -> instance)
      # Hooks can modify params and messages for logging, filtering, PII redaction, etc.
      run_before_completion_hooks(params, messages)

      begin
        response = ruby_llm_request(params:, model: openai || model, messages:, openai_override: openai)
        retry_count = 0
        content = nil

        # no need for additional processing if streaming
        return if stream && response.blank?

        # tuck the full response into a thread local in case needed
        Thread.current[:chat_completion_response] = response.is_a?(Hash) ? response.with_indifferent_access : response

        # TODO: add a standardized callback hook for usage events
        # broadcast(:usage_event, usage_subject, self.class.name.to_s, response, premium?)

        tool_calls = response.dig("choices", 0, "message", "tool_calls") || []
        if tool_calls.any?
          tool_call_count += tool_calls.size

          # Check if we've exceeded max_tool_calls
          if tool_call_count > self.max_tool_calls
            # Add system message about hitting the limit
            messages << { role: "system", content: "Maximum tool calls (#{self.max_tool_calls}) exceeded. Please provide a final response to the user without calling any more tools." }

            # Force a final response without tools
            params[:tools] = nil
            response = ruby_llm_request(params:, model: openai || model, messages:, openai_override: openai)

            # Process the final response
            content = response.dig("choices", 0, "message", "content")
            transcript << { assistant: content } if save_response
            return raw ? response : content.strip
          end

          # Dispatch tool calls
          tool_calls.each do |tool_call| # TODO: parallelize this?
            # dispatch the called function
            function_name = tool_call["function"]["name"]
            arguments = JSON.parse(tool_call["function"]["arguments"].presence || "{}")
            raise "Unauthorized function call: #{function_name}" unless self.class.functions.map { |f| f[:name].to_sym }.include?(function_name.to_sym)

            dispatch_tool_function(function_name, arguments.with_indifferent_access)
          end

          # After executing tool calls, we need to continue the conversation
          # to let the AI process the results and provide a text response.
          # We continue until the AI responds with a regular assistant message
          # (not another tool call request), unless stop_tool_calls_and_respond! was called.

          # Use the updated transcript for the next call, not the original messages
          updated_messages = transcript.flatten.compact
          last_message = updated_messages.last

          if !@stop_tool_calls_and_respond && (last_message[:role] != "assistant" || last_message[:tool_calls].present?)
            # Send the updated transcript back to the AI
            return chat_completion(
              params:,
              json:,
              raw:,
              openai:,
              save_response:,
              messages: nil, # Use transcript instead
              available_tools:,
              max_tool_calls: self.max_tool_calls - tool_call_count
            )
          elsif @stop_tool_calls_and_respond
            # If stop_tool_calls_and_respond was set, force a final response without tools
            params[:tools] = nil
            response = ruby_llm_request(params:, model: openai || model, messages:, openai_override: openai)

            content = response.dig("choices", 0, "message", "content")
            transcript << { assistant: content } if save_response
            return raw ? response : content.strip
          end
        end

        response.tap do |res|
          content = res.dig("choices", 0, "message", "content")

          transcript << { assistant: content } if save_response
          content = content.strip

          if json
            # Make automatic JSON parsing available to non-OpenAI providers that don't support the response_format parameter
            content = content.match(%r{<json>(.*?)</json>}m)[1] if content.include?("<json>")

            return JSON.parse(content)
          end

          return content unless raw
        end
      rescue JSON::ParserError => e
        if e.message.include?("not a valid") # blank JSON
          warn "Retrying blank JSON response... (#{retry_count} attempts) #{e.message}"
          retry_count += 1
          sleep 1 * retry_count # backoff
          retry if retry_count < 3

          raise e # just fail if we can't get content after 3 attempts
        end

        warn "Bad JSON received!!!!!!: #{content}"
        raise e
      rescue Faraday::BadRequestError => e
        # make sure we see the actual error message on console or Honeybadger
        warn "Chat completion failed!!!!!!!!!!!!!!!!: #{e.response[:body]}"
        raise e
      end
    end

    # This method returns the transcript array.
    # Manually add your messages to it in the following abbreviated format
    # before calling `chat_completion`.
    #
    # { system: "You are a pumpkin" },
    # { user: "Hey what time is it?" },
    # { assistant: "Sorry, pumpkins do not wear watches" }
    #
    # to add a function call use the following format:
    # { function: { name: 'fancy_pants_function', arguments: { param: 'value' } } }
    #
    # to add a function result use the following format:
    # { function: result, name: 'fancy_pants_function' }
    #
    # @return [Array] The transcript array.
    def transcript
      @transcript ||= TranscriptAdapter.new(ruby_llm_chat)
    end

    # Returns the RubyLLM::Chat instance for this conversation
    def ruby_llm_chat
      @ruby_llm_chat ||= begin
        model_id = model || configuration.model

        # Determine provider based on model format or explicit openai flag
        provider = if model_id.to_s.start_with?("openai/") || model_id.to_s.match?(/^gpt-/)
                     :openai
                   else
                     :openrouter
                   end

        RubyLLM.chat(model: model_id, provider:, assume_model_exists: true)
      end
    end

    # Dispatches a tool function call with the given function name and arguments.
    # This method can be overridden in subclasses to customize how function calls are handled.
    #
    # @param function_name [String] The name of the function to call
    # @param arguments [Hash] The arguments to pass to the function
    # @param cache [ActiveSupport::Cache] Optional cache object
    # @return [Object] The result of the function call
    def dispatch_tool_function(function_name, arguments, cache: nil)
      public_send(function_name, arguments, cache)
    end

    private

    def filtered_tools(tool_names)
      return nil if tool_names.blank?

      requested_tools = tool_names.map(&:to_sym)
      available_tool_names = tools.map { |tool| tool.dig(:function, :name).to_sym }

      undeclared_tools = requested_tools - available_tool_names
      raise UndeclaredToolError, "Undeclared tools: #{undeclared_tools.join(", ")}" if undeclared_tools.any?

      tools.select { |tool| requested_tools.include?(tool.dig(:function, :name).to_sym) }
    end

    def run_before_completion_hooks(params, messages)
      hooks = [
        Raix.configuration.before_completion,
        self.class.configuration.before_completion,
        before_completion
      ].compact

      return if hooks.empty?

      context = CompletionContext.new(
        chat_completion: self,
        messages:,
        params:
      )

      hooks.each do |hook|
        result = hook.call(context) if hook.respond_to?(:call)
        next unless result.is_a?(Hash)

        # Handle model separately since it's passed as a keyword arg to ruby_llm_request
        self.model = result[:model] if result.key?(:model)
        params.merge!(result.compact)
      end
    end

    def ruby_llm_request(params:, model:, messages:, openai_override: nil)
      # Create a temporary chat instance for this request
      provider = determine_provider(model, openai_override)
      chat = RubyLLM.chat(model:, provider:, assume_model_exists: true)

      # Apply messages to the chat
      # Track if we have a user message to determine how to call ask
      has_user_message = false

      messages.each do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]

        case role.to_s
        when "system"
          chat.with_instructions(content)
        when "user"
          has_user_message = true
          chat.add_message(role: :user, content:)
        when "assistant"
          if msg[:tool_calls] || msg["tool_calls"]
            chat.add_message(role: :assistant, content:, tool_calls: msg[:tool_calls] || msg["tool_calls"])
          else
            chat.add_message(role: :assistant, content:)
          end
        when "tool"
          chat.add_message(
            role: :tool,
            content:,
            tool_call_id: msg[:tool_call_id] || msg["tool_call_id"]
          )
        end
      end

      # Apply configuration parameters
      chat.with_temperature(params[:temperature]) if params[:temperature]

      # Apply additional params (RubyLLM with_params expects keyword args)
      additional_params = params.compact.except(:temperature, :tools, :max_tokens, :max_completion_tokens)
      chat.with_params(**additional_params) if additional_params.any?

      # Handle tools - convert Raix function declarations to RubyLLM tools
      if params[:tools].present? && respond_to?(:class) && self.class.respond_to?(:functions)
        ruby_llm_tools = FunctionToolAdapter.convert_tools_for_ruby_llm(self)
        ruby_llm_tools.each { |tool| chat.with_tool(tool) }
      end

      # Execute the completion
      if stream.present?
        # Streaming mode
        if has_user_message
          chat.complete(&stream)
        else
          chat.ask(&stream)
        end
        nil # Return nil for streaming as per original behavior
      else
        # Non-streaming mode - return OpenAI-compatible response format
        response_message = has_user_message ? chat.complete : chat.ask

        # Convert RubyLLM response to OpenAI format for compatibility
        {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => response_message.content,
                "tool_calls" => response_message.tool_calls
              },
              "finish_reason" => response_message.tool_call? ? "tool_calls" : "stop"
            }
          ],
          "usage" => {
            "prompt_tokens" => response_message.input_tokens,
            "completion_tokens" => response_message.output_tokens,
            "total_tokens" => (response_message.input_tokens || 0) + (response_message.output_tokens || 0)
          }
        }
      end
    rescue StandardError => e
      warn "RubyLLM request failed: #{e.message}"
      raise e
    end

    def determine_provider(model, openai_override)
      return :openai if openai_override
      return :openai if model.to_s.match?(/^gpt-/) || model.to_s.match?(/^o\d/)

      # Default to openrouter for model IDs with provider prefix
      :openrouter
    end
  end
end
