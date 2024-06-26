# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/object/blank"
require "open_router"
require "openai"

module Raix
  # The `ChatCompletion`` module is a Rails concern that provides a way to interact
  # with the OpenRouter Chat Completion API via its client. The module includes a few
  # methods that allow you to build a transcript of messages and then send them to
  # the API for completion. The API will return a response that you can use however
  # you see fit. If the response includes a function call, the module will dispatch
  # the function call and return the result. Which implies that function calls need
  # to be defined on the class that includes this module. (Note: You should probably
  # use the `FunctionDispatch` module to define functions instead of doing it manually.)
  module ChatCompletion
    extend ActiveSupport::Concern

    attr_accessor :frequency_penalty, :logit_bias, :logprobs, :loop, :min_p, :model, :presence_penalty,
                  :repetition_penalty, :response_format, :stream, :temperature, :max_tokens, :seed, :stop, :top_a,
                  :top_k, :top_logprobs, :top_p, :tools, :tool_choice, :provider

    # This method performs chat completion based on the provided transcript and parameters.
    #
    # @param params [Hash] The parameters for chat completion.
    # @option loop [Boolean] :loop (false) Whether to loop the chat completion after function calls.
    # @option params [Boolean] :json (false) Whether to return the parse the response as a JSON object.
    # @option params [Boolean] :openai (false) Whether to use OpenAI's API instead of OpenRouter's.
    # @option params [Boolean] :raw (false) Whether to return the raw response or dig the text content.
    # @return [String|Hash] The completed chat response.
    def chat_completion(params: {}, loop: false, json: false, raw: false, openai: false)
      messages = transcript.flatten.compact.map { |msg| transform_message_format(msg) }
      raise "Can't complete an empty transcript" if messages.blank?

      # used by FunctionDispatch
      self.loop = loop

      # set params to default values if not provided
      params[:frequency_penalty] ||= frequency_penalty.presence
      params[:logit_bias] ||= logit_bias.presence
      params[:logprobs] ||= logprobs.presence
      params[:max_tokens] ||= max_tokens.presence || Raix.configuration.max_tokens
      params[:min_p] ||= min_p.presence
      params[:presence_penalty] ||= presence_penalty.presence
      params[:provider] ||= provider.presence
      params[:repetition_penalty] ||= repetition_penalty.presence
      params[:response_format] ||= response_format.presence
      params[:seed] ||= seed.presence
      params[:stop] ||= stop.presence
      params[:temperature] ||= temperature.presence || Raix.configuration.temperature
      params[:tool_choice] ||= tool_choice.presence
      params[:tools] ||= tools.presence
      params[:top_a] ||= top_a.presence
      params[:top_k] ||= top_k.presence
      params[:top_logprobs] ||= top_logprobs.presence
      params[:top_p] ||= top_p.presence

      if json
        params[:provider] ||= {}
        params[:provider][:require_parameters] = true
        params[:response_format] ||= {}
        params[:response_format][:type] = "json_object"
      end

      # set the model to the default if not provided
      self.model ||= Raix.configuration.model

      begin
        response = if openai
                     openai_request(params:, model: openai,
                                    messages:)
                   else
                     openrouter_request(
                       params:, model:, messages:
                     )
                   end
        retry_count = 0
        content = nil

        # no need for additional processing if streaming
        return if stream && response.blank?

        # tuck the full response into a thread local in case needed
        Thread.current[:chat_completion_response] = response.with_indifferent_access

        # TODO: add a standardized callback hook for usage events
        # broadcast(:usage_event, usage_subject, self.class.name.to_s, response, premium?)

        # TODO: handle parallel tool calls
        if (function = response.dig("choices", 0, "message", "tool_calls", 0, "function"))
          @current_function = function["name"]
          # dispatch the called function
          arguments = JSON.parse(function["arguments"].presence || "{}")
          arguments[:bot_message] = bot_message if respond_to?(:bot_message)
          return send(function["name"], arguments.with_indifferent_access)
        end

        response.tap do |res|
          content = res.dig("choices", 0, "message", "content")
          if json
            content = content.squish
            return JSON.parse(content)
          end

          return content unless raw
        end
      rescue JSON::ParserError => e
        if e.message.include?("not a valid") # blank JSON
          puts "Retrying blank JSON response... (#{retry_count} attempts) #{e.message}"
          retry_count += 1
          sleep 1 * retry_count # backoff
          retry if retry_count < 3

          raise e # just fail if we can't get content after 3 attempts
        end

        # attempt to fix the JSON
        JsonFixer.new.call(content, e.message)
      rescue Faraday::BadRequestError => e
        # make sure we see the actual error message on console or Honeybadger
        puts "Chat completion failed!!!!!!!!!!!!!!!!: #{e.response[:body]}"
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
    # to add a function result use the following format:
    # { function: result, name: 'fancy_pants_function' }
    #
    # @return [Array] The transcript array.
    def transcript
      @transcript ||= []
    end

    private

    def openai_request(params:, model:, messages:)
      params[:stream] ||= stream.presence
      Raix.configuration.openai_client.chat(parameters: params.compact.merge(model:, messages:))
    end

    def openrouter_request(params:, model:, messages:)
      retry_count = 0

      begin
        Raix.configuration.openrouter_client.complete(messages, model:, extras: params.compact, stream:)
      rescue OpenRouter::ServerError => e
        if e.message.include?("retry")
          puts "Retrying OpenRouter request... (#{retry_count} attempts) #{e.message}"
          retry_count += 1
          sleep 1 * retry_count # backoff
          retry if retry_count < 5
        end

        raise e
      end
    end

    def transform_message_format(message)
      return message if message[:role].present?

      if message[:function].present?
        { role: "assistant", name: message.dig(:function, :name), content: message.dig(:function, :arguments).to_json }
      elsif message[:result].present?
        { role: "function", name: message[:name], content: message[:result] }
      else
        { role: message.first.first, content: message.first.last }
      end
    end
  end
end
