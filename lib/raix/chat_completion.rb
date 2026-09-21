# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/module/delegation"
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
    delegate :configuration, to: :class

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
      complete_conversation(params:, loop:, json:, raw:, openai:, save_response:, messages:, available_tools:, max_tool_calls:)
    end

    # The body of chat_completion. Continuation rounds after a tool call recurse
    # here directly rather than through the public method, which a subclass may
    # override with a different signature (PromptDeclarations does).
    def complete_conversation(params: {}, loop: false, json: false, raw: false, openai: nil, save_response: true, messages: nil, available_tools: nil, max_tool_calls: nil)
      # Work on a copy: defaults are filled in and tool_choice is dropped between
      # rounds, and none of that should leak into a Hash the caller may reuse.
      params = params.dup

      # set params to default values if not provided
      params[:cache_at] ||= cache_at.presence
      params[:frequency_penalty] ||= frequency_penalty.presence
      params[:logit_bias] ||= logit_bias.presence
      params[:logprobs] ||= logprobs.presence
      params[:max_completion_tokens] ||= max_completion_tokens.presence || configuration.max_completion_tokens
      params[:max_tokens] ||= max_tokens.presence || configuration.max_tokens
      params[:min_p] ||= min_p.presence
      if (predicted = params[:prediction] || prediction.presence)
        # Continuation rounds pass an already-wrapped prediction back through
        # here, so only wrap a bare value.
        params[:prediction] = predicted.is_a?(Hash) && predicted.with_indifferent_access[:type] == "content" ? predicted : { type: "content", content: predicted }
      end
      params[:presence_penalty] ||= presence_penalty.presence
      params[:provider] ||= provider.presence
      params[:repetition_penalty] ||= repetition_penalty.presence
      params[:response_format] ||= response_format.presence
      params[:seed] ||= seed.presence
      params[:stop] ||= stop.presence
      params[:temperature] ||= temperature.presence || configuration.temperature
      # A forced tool_choice applies to the first round only. Continuation
      # rounds (depth > 0) leave it unset so the model can answer in text once
      # its tool results are in.
      params[:tool_choice] ||= tool_choice.presence if @tool_loop_depth.to_i.zero?
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
        # Build fresh nested hashes rather than writing into ones the caller
        # handed us; the dup above is shallow.
        params[:provider] = (params[:provider] || {}).merge(require_parameters: true) unless openai
        params[:response_format] = { type: "json_object" } if params[:response_format].blank?
      end

      # Deprecation warning for loop parameter
      if loop
        warn "\n\nWARNING: The 'loop' parameter is DEPRECATED and will be ignored.\nChat completions now automatically continue after tool calls until the AI provides a text response.\nUse 'max_tool_calls' to limit the number of tool calls (default: #{configuration.max_tool_calls}).\n\n"
      end

      # Set max_tool_calls from parameter or configuration default
      self.max_tool_calls = max_tool_calls || configuration.max_tool_calls

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

      # Each continuation after a tool round recurses with the allowance that is
      # left, so remember the budget the caller actually asked for. That is the
      # number the limit message has to quote.
      @tool_loop_depth = @tool_loop_depth.to_i + 1
      @max_tool_calls_budget = self.max_tool_calls if @tool_loop_depth == 1

      # Start this loop with a clear stop flag and hand back whatever was set
      # on entry when it returns. A nested chat_completion inside a tool body
      # must neither erase a stop the enclosing loop's tool already requested
      # nor leak its own stop into that loop.
      stop_on_entry = @stop_tool_calls_and_respond
      @stop_tool_calls_and_respond = false

      # True only while parsing the model's final JSON response. The blank-JSON
      # retry below must never fire for a JSON::ParserError raised by a tool
      # body (in this frame or a continuation round), which would re-issue the
      # request and run tools again.
      parsing_response = false

      begin
        response = ruby_llm_request(params:, model: openai || model, messages:, openai_override: openai)

        retry_count = 0
        content = nil

        # Nothing came back to process (a streamed request that produced no message).
        return if response.blank?

        # tuck the full response into a thread local in case needed
        Thread.current[:chat_completion_response] = response.with_indifferent_access

        # TODO: add a standardized callback hook for usage events
        # broadcast(:usage_event, usage_subject, self.class.name.to_s, response, premium?)

        # The model's own turn, kept intact (tool calls with their ids and
        # signatures, reasoning details) so it can be replayed verbatim.
        assistant_turn = (response.dig("choices", 0, "message") || {}).with_indifferent_access
        tool_calls = assistant_turn[:tool_calls] || []
        if tool_calls.any?
          # Enforce the budget per call rather than per round: a single model
          # response can pack several parallel tool calls, and the ones that
          # still fit under the cap should run.
          allowance = [self.max_tool_calls - tool_call_count, 0].max
          cap_exceeded = tool_calls.size > allowance
          tool_call_count += [tool_calls.size, allowance].min

          # A call is authorized only if the function is declared on this class
          # AND was offered on this request (the available_tools-filtered set).
          # Declared-only would let a hidden tool through; offered-only would
          # trust a hook-supplied name.
          declared = self.class.respond_to?(:functions) ? Array(self.class.functions).map { |function| function[:name].to_s } : []
          offered = tool_names_from(params[:tools]) & declared

          # Every call the model made gets a result message, refused ones
          # included, so the exchange replayed to the provider stays well-formed.
          # Results accumulate as tools run: if one raises, the exchange is
          # still recorded (failure and unexecuted calls spelled out) before the
          # error propagates, so a retry sees what already happened.
          tool_results = []
          begin
            tool_calls.each_with_index do |tool_call, index| # TODO: parallelize this?
              result = if index < allowance
                         execute_tool_call(tool_call, offered:)
                       else
                         "Tool call refused: maximum tool calls (#{@max_tool_calls_budget}) exceeded."
                       end

              tool_results << tool_result_message(tool_call, result)
            end
          rescue StandardError => e
            # The exception class is recorded, not its message: error text can
            # carry response bodies, SQL, or credentials the model must not see.
            failed, *unexecuted = tool_calls.drop(tool_results.size)
            tool_results << tool_result_message(failed, "Tool call failed (#{e.class}).") if failed
            unexecuted.each { |tool_call| tool_results << tool_result_message(tool_call, "Not executed: an earlier tool call in this batch failed.") }
            transcript << [assistant_turn, *tool_results] if save_response
            raise
          end

          # Record the authoritative exchange (the model's ids and signatures,
          # not synthetic ones) so a later chat_completion on this transcript can
          # replay it faithfully, then continue from it. `save_response: false`
          # keeps the exchange out of the transcript along with the final answer,
          # which is how a nested chat_completion inside a tool body keeps its
          # internal rounds out of the outer conversation's history.
          transcript << [assistant_turn, *tool_results] if save_response
          messages += [assistant_turn, *tool_results]

          # A cap breach or stop_tool_calls_and_respond! ends the conversation
          # with one final, tool-less completion that goes through the same
          # response handling below. Otherwise let the AI process the tool
          # results and either answer or call more tools.
          if cap_exceeded || @stop_tool_calls_and_respond
            response = force_final_response(params:, openai:, messages:, cap_exceeded:)
            Thread.current[:chat_completion_response] = response.with_indifferent_access
          else
            # Drop a forced tool_choice before continuing, the way
            # force_final_response does: re-sending "required" (or a named
            # function) on every round would keep the model calling tools until
            # the budget ran out instead of letting it answer.
            params.delete(:tool_choice)

            return complete_conversation(
              params:,
              json:,
              raw:,
              openai:,
              save_response:,
              messages:,
              available_tools:,
              max_tool_calls: self.max_tool_calls - tool_call_count
            )
          end
        end

        response.tap do |res|
          content = res.dig("choices", 0, "message", "content")

          transcript << { assistant: content } if save_response
          content = content.to_s.strip

          if json
            # Make automatic JSON parsing available to non-OpenAI providers that don't support the response_format parameter
            content = content.match(%r{<json>(.*?)</json>}m)[1] if content.include?("<json>")

            parsing_response = true
            return JSON.parse(content)
          end

          return content unless raw
        end
      rescue JSON::ParserError => e
        # Only a parse failure of the model's own response is worth a retry.
        raise e unless parsing_response

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
      ensure
        @tool_loop_depth -= 1
        @max_tool_calls_budget = nil if @tool_loop_depth.zero?
        @stop_tool_calls_and_respond = stop_on_entry
      end
    end
    private :complete_conversation

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

        RubyLLM.chat(model: model_id, provider:, protocol: :chat_completions, assume_model_exists: true)
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

    # Runs one tool call with this loop's bookkeeping shielded from
    # re-entrancy. FunctionDispatch executes tool bodies on this same instance,
    # so a tool that calls chat_completion again (a sub-agent pattern) would
    # otherwise overwrite the outer loop's max_tool_calls, depth and budget,
    # and reset a stop flag an earlier tool in this batch raised. The nested
    # call starts from a clean slate and the outer values come back afterwards.
    def dispatch_preserving_loop_state(function_name, arguments)
      saved = [max_tool_calls, @tool_loop_depth, @max_tool_calls_budget, @stop_tool_calls_and_respond]

      @tool_loop_depth = 0
      @max_tool_calls_budget = nil
      @stop_tool_calls_and_respond = false
      dispatch_tool_function(function_name, arguments)
    ensure
      # A stop this tool requested belongs to this loop. A nested
      # chat_completion puts back the flag it found on entry, so a stop raised
      # inside it never shows up here.
      stop_requested_here = @stop_tool_calls_and_respond
      self.max_tool_calls, @tool_loop_depth, @max_tool_calls_budget, @stop_tool_calls_and_respond = saved
      @stop_tool_calls_and_respond ||= stop_requested_here
    end

    def tool_result_message(tool_call, content)
      { role: "tool", tool_call_id: tool_call[:id], name: tool_call.dig(:function, :name), content: content.to_s }
    end

    # Authorizes and runs one tool call from the model, returning the value the
    # tool result message carries back. A call for a tool that was not offered,
    # or with a malformed argument payload, is reported to the model as a tool
    # error rather than raised: earlier calls in the same batch may already
    # have done their work, and the model can recover from a result.
    def execute_tool_call(tool_call, offered:)
      function_name = tool_call.dig(:function, :name).to_s
      return "Tool call refused: #{function_name} is not available on this request." unless offered.include?(function_name)

      # Only a missing or empty payload means "no arguments"; whitespace or any
      # other unparseable text is malformed and must not run the tool.
      raw_arguments = tool_call.dig(:function, :arguments).to_s
      begin
        arguments = raw_arguments.empty? ? {} : JSON.parse(raw_arguments)
      rescue JSON::ParserError
        return "Invalid arguments for #{function_name}: malformed JSON"
      end
      return "Invalid arguments for #{function_name}: expected a JSON object, got #{arguments.class}" unless arguments.is_a?(Hash)

      dispatch_preserving_loop_state(function_name, arguments.with_indifferent_access)
    end

    # Issues the single final completion that ends a conversation cut short by
    # the max_tool_calls budget or by stop_tool_calls_and_respond!, and returns
    # the OpenAI-compatible hash.
    def force_final_response(params:, openai:, messages:, cap_exceeded:)
      if cap_exceeded
        messages += [{ role: "system",
                       content: "Maximum tool calls (#{@max_tool_calls_budget}) exceeded. Please provide a final response to the user without calling any more tools." }]
      end

      # Force a final response without tools. Drop tool_choice as well: a
      # lingering tool_choice that forces tool use with no tools registered is a
      # provider error.
      final_params = params.dup
      final_params[:tools] = nil
      final_params.delete(:tool_choice)

      ruby_llm_request(params: final_params, model: openai || model, messages:, openai_override: openai)
    end

    # Function names declared by an OpenAI-shaped tools array. Tolerates string
    # keys, since a before_completion hook may hand back tools that went
    # through JSON.
    def tool_names_from(tools)
      Array(tools).map { |tool| tool.with_indifferent_access.dig(:function, :name).to_s }
    end

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
      chat = RubyLLM.chat(model:, provider:, protocol: :chat_completions, assume_model_exists: true)

      # Apply messages to the chat. Structured content arrays (multipart text,
      # images, Anthropic-style cache_control) are taken apart first, because
      # RubyLLM messages only carry String content.
      caching = false
      cache_ttl = nil

      messages.each do |msg|
        role = msg[:role] || msg["role"]
        part = MultimodalContentAdapter.translate(msg[:content] || msg["content"])
        content = part.content
        caching ||= part.cache_boundary?
        cache_ttl ||= part.cache_ttl

        case role.to_s
        when "system"
          chat.with_instructions(content, append: true, cache_until_here: part.cache_boundary?)
        when "user"
          # A user turn must carry content on the wire. With attachments RubyLLM
          # builds the parts itself; without them nil would be dropped from the
          # payload entirely, which providers reject.
          content = "" if content.nil? && part.attachments.empty?
          added = chat.add_message(role: :user, content:, attachments: part.attachments)
          added.cache_until_here if part.cache_boundary?
        when "assistant"
          tool_calls = msg[:tool_calls] || msg["tool_calls"]
          # RubyLLM requires the :content key even when nil (a tool-call turn);
          # an assistant turn with neither content nor tool calls needs "" so
          # the provider still receives a content field.
          content = "" if content.nil? && tool_calls.blank?
          attrs = { role: :assistant, content: }
          attrs[:tool_calls] = normalize_tool_calls_for_ruby_llm(tool_calls) if tool_calls
          # Signed reasoning has to make the round trip for multi-round tool use
          # on models that require it (OpenRouter reasoning_details, Gemini
          # thought signatures).
          reasoning = {
            raw_reasoning: msg[:raw_reasoning] || msg["raw_reasoning"],
            thinking: msg[:thinking] || msg["thinking"],
            thinking_signature: msg[:thinking_signature] || msg["thinking_signature"]
          }.compact
          added = chat.add_message(attrs.merge(reasoning))
          added.cache_until_here if part.cache_boundary?
        when "tool"
          chat.add_message(
            role: :tool,
            content:,
            tool_call_id: msg[:tool_call_id] || msg["tool_call_id"]
          )
        end
      end

      # Render the cache boundaries marked above; without this RubyLLM sends no
      # cache controls at all. A ttl from the content's cache_control rides along.
      chat.with_caching({ ttl: cache_ttl }.compact) if caching

      # Apply configuration parameters
      chat.with_temperature(params[:temperature]) if params[:temperature]
      if (max_output_tokens = params[:max_completion_tokens] || params[:max_tokens])
        chat.with_max_output_tokens(max_output_tokens)
      end

      # Apply additional params. RubyLLM sends provider options into the
      # request payload verbatim, which is what these OpenAI/OpenRouter-shaped
      # knobs (top_p, seed, response_format, provider routing, ...) expect.
      additional_params = params.compact.except(:temperature, :tools, :max_tokens, :max_completion_tokens)
      chat.with_provider_options(additional_params) if additional_params.any?

      # Handle tools - convert Raix function declarations to RubyLLM tools.
      # params[:tools] already reflects `available_tools`, so only the
      # functions it names are registered with the chat.
      if params[:tools].present? && respond_to?(:class) && self.class.respond_to?(:functions)
        chat.with_tools(*FunctionToolAdapter.convert_tools_for_ruby_llm(self, only: tool_names_from(params[:tools])))
      end

      # Execute the completion. Raix drives the tool loop itself (see
      # #chat_completion), so this asks RubyLLM for exactly one completion and
      # leaves any tool calls in the response unexecuted. A streaming request
      # yields chunks to the block and still returns the assembled message, so
      # tool calls made mid-stream get dispatched like any other.
      response_message = stream.present? ? chat.generate(&stream) : chat.generate
      return nil if response_message.nil?

      # Pull through the raw provider payload when available. OpenRouter's
      # `id` is the only handle we have to look up authoritative billing
      # cost via /api/v1/generation, and callers that watch the response
      # snapshot for `model` / cached-token counts shouldn't have to break
      # out of the OpenAI-compatible shape to get them.
      raw_body = response_message.raw.respond_to?(:body) ? response_message.raw.body : nil
      raw_body = {} unless raw_body.is_a?(Hash)
      upstream_usage = raw_body["usage"].is_a?(Hash) ? raw_body["usage"] : {}

      # Prefer the provider's own counts. RubyLLM's input figure excludes cached
      # tokens, and only the provider knows the authoritative totals; its
      # prompt_tokens_details / completion_tokens_details ride along untouched.
      tokens = response_message.tokens
      prompt_tokens = upstream_usage["prompt_tokens"] || [tokens.input, tokens.cache_read, tokens.cache_write].compact.sum
      completion_tokens = upstream_usage["completion_tokens"] || tokens.output
      usage_payload = upstream_usage.merge(
        "prompt_tokens" => prompt_tokens,
        "completion_tokens" => completion_tokens,
        "total_tokens" => upstream_usage["total_tokens"] || (prompt_tokens.to_i + completion_tokens.to_i)
      )

      # The assistant turn carries what a continuation round has to replay:
      # tool calls with their ids and signatures, plus any signed reasoning.
      message = {
        "role" => "assistant",
        "content" => response_message.content,
        "tool_calls" => serialize_tool_calls(response_message.tool_calls)
      }
      message["raw_reasoning"] = response_message.raw_reasoning if response_message.raw_reasoning
      if (thinking = response_message.thinking)
        message["thinking"] = thinking.text
        message["thinking_signature"] = thinking.signature
      end

      {
        "id" => raw_body["id"],
        "model" => raw_body["model"] || response_message.model,
        "provider" => raw_body["provider"],
        "choices" => [
          {
            "message" => message,
            "finish_reason" => response_message.tool_call? ? "tool_calls" : "stop"
          }
        ],
        "usage" => usage_payload
      }
    rescue RubyLLM::ToolCallParseError => e
      # RubyLLM rejects a response whose tool arguments are not valid JSON before
      # Raix ever sees a Message. Rebuild the assistant turn from the raw payload
      # so the loop can answer each call with a tool error instead of aborting.
      response = assistant_turn_from_raw_response(e.response)
      raise e unless response

      response
    rescue StandardError => e
      warn "RubyLLM request failed: #{e.message}"
      raise e
    end

    # The OpenAI-compatible response hash for a provider payload RubyLLM could
    # not parse into a Message, or nil when the payload has no tool calls to
    # recover. Arguments stay as the provider sent them.
    def assistant_turn_from_raw_response(raw)
      body = raw.respond_to?(:body) ? raw.body : nil
      return unless body.is_a?(Hash)

      raw_message = body.dig("choices", 0, "message")
      return unless raw_message.is_a?(Hash) && raw_message["tool_calls"].is_a?(Array)

      # Replay keys tool calls by id, so a payload with missing or duplicate
      # ids cannot be recovered into a valid exchange.
      ids = raw_message["tool_calls"].map { |tool_call| tool_call["id"].to_s }
      return if ids.any?(&:empty?) || ids.uniq.size != ids.size

      # Keep the signed state RubyLLM would have extracted: OpenRouter's
      # reasoning_details array and Gemini's per-call thought signature, which
      # the wire nests under extra_content.google.
      message = {
        "role" => "assistant",
        "content" => raw_message["content"],
        "tool_calls" => raw_message["tool_calls"].map do |tool_call|
          signature = tool_call.dig("extra_content", "google", "thought_signature")
          signature ? tool_call.merge("thought_signature" => signature) : tool_call
        end
      }
      message["raw_reasoning"] = raw_message["reasoning_details"] if raw_message["reasoning_details"].is_a?(Array)

      {
        "id" => body["id"],
        "model" => body["model"],
        "provider" => body["provider"],
        "choices" => [{ "message" => message, "finish_reason" => "tool_calls" }],
        "usage" => body["usage"].is_a?(Hash) ? body["usage"] : {}
      }
    end

    def determine_provider(model, openai_override)
      return :openai if openai_override
      return :openai if model.to_s.match?(/^gpt-/) || model.to_s.match?(/^o\d/)

      # Default to openrouter for model IDs with provider prefix
      :openrouter
    end

    # Renders RubyLLM's tool calls (a Hash keyed by call id whose values are
    # RubyLLM::ToolCall) as OpenAI's array-of-hashes shape, which is what the
    # response hash Raix hands back to callers — and its own tool loop — reads.
    def serialize_tool_calls(tool_calls)
      return nil if tool_calls.blank?

      tool_calls.values.map do |tool_call|
        serialized = {
          "id" => tool_call.id,
          "type" => "function",
          "function" => {
            "name" => tool_call.name,
            "arguments" => tool_call.arguments.to_json
          }
        }
        serialized["thought_signature"] = tool_call.thought_signature if tool_call.thought_signature
        serialized
      end
    end

    # Arguments replayed from a recorded tool call. RubyLLM re-serializes them
    # as JSON, so a payload the provider sent malformed (already answered with
    # a tool error) is replayed as an empty object rather than raising again.
    def parse_replayed_arguments(arguments)
      return {} if arguments.blank?

      parsed = JSON.parse(arguments)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # Raix's transcript stores assistant tool calls in OpenAI's array-of-hashes
    # shape (`[{ id:, type:, function: { name:, arguments: } }]`), but RubyLLM's
    # providers format tool calls from a Hash keyed by call id whose values
    # respond to #id/#name/#arguments (RubyLLM::ToolCall). Translate so a
    # transcript that already contains tool exchanges can be replayed back into
    # a fresh RubyLLM chat on every continuation round, including the forced
    # final completion after a max_tool_calls cap breach or
    # stop_tool_calls_and_respond!.
    def normalize_tool_calls_for_ruby_llm(tool_calls)
      return tool_calls if tool_calls.is_a?(Hash) && tool_calls.values.all?(RubyLLM::ToolCall)

      Array(tool_calls).each_with_object({}) do |raw, acc|
        tc = raw.respond_to?(:with_indifferent_access) ? raw.with_indifferent_access : raw
        function = tc[:function] || {}
        arguments = function[:arguments]
        arguments = parse_replayed_arguments(arguments) if arguments.is_a?(String)
        acc[tc[:id]] = RubyLLM::ToolCall.new(id: tc[:id], name: function[:name], arguments: arguments || {}, thought_signature: tc[:thought_signature])
      end
    end
  end
end
