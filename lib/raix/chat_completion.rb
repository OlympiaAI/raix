# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/indifferent_access"

require_relative "message_adapters/base"
require_relative "transcript_store"
require_relative "runtime/errors"
require_relative "runtime/transport"
require_relative "runtime/stream_parser"
require_relative "runtime/stream_accumulator"
require_relative "runtime/providers/base"
require_relative "runtime/providers/openai"
require_relative "runtime/providers/openrouter"
require_relative "runtime/client"

module Raix
  class UndeclaredToolError < StandardError; end

  # Chat completion concern with tool orchestration and hook support.
  module ChatCompletion
    extend ActiveSupport::Concern

    attr_accessor :before_completion, :cache_at, :frequency_penalty, :logit_bias, :logprobs, :loop, :min_p, :model,
                  :presence_penalty, :prediction, :repetition_penalty, :response_format, :stream, :temperature,
                  :max_completion_tokens, :max_tokens, :seed, :stop, :top_a, :top_k, :top_logprobs, :top_p, :tools,
                  :available_tools, :tool_choice, :provider, :max_tool_calls, :stop_tool_calls_and_respond

    class_methods do
      def configuration
        @configuration ||= Configuration.new(fallback: Raix.configuration)
      end

      def configure
        yield(configuration)
      end
    end

    def configuration
      self.class.configuration
    end

    def chat_completion(params: {}, loop: false, json: false, raw: false, openai: nil, save_response: true, messages: nil, available_tools: nil, max_tool_calls: nil)
      params = build_request_params(params.dup, available_tools:)
      json = true if params[:response_format].is_a?(Raix::ResponseFormat)
      params[:response_format] = params[:response_format].to_schema if params[:response_format].is_a?(Raix::ResponseFormat)
      params = apply_json_mode_params(params, json:, openai:)

      warn_deprecated_loop(loop)
      self.max_tool_calls = max_tool_calls || configuration.max_tool_calls
      @stop_tool_calls_and_respond = false
      self.model ||= configuration.model

      adapter = MessageAdapters::Base.new(self)
      messages ||= transcript.flatten.compact
      messages = messages.map { |msg| adapter.transform(msg) }.dup
      raise "Can't complete an empty transcript" if messages.blank?

      run_before_completion_hooks(params, messages)

      retry_count = 0
      tool_call_count = 0
      content = nil

      begin
        response = execute_runtime_request(params:, model: openai || model, messages:, openai_override: openai)
        return if stream && response.blank?

        Thread.current[:chat_completion_response] = response.is_a?(Hash) ? response.with_indifferent_access : response

        tool_calls = response.dig("choices", 0, "message", "tool_calls") || []
        if tool_calls.any?
          tool_call_count += tool_calls.size
          return handle_tool_calls(tool_calls:, tool_call_count:, params:, json:, raw:, openai:, save_response:, available_tools:)
        end

        content = response.dig("choices", 0, "message", "content")
        transcript << { assistant: content } if save_response
        return response if raw

        content = content.to_s.strip
        return parse_json_response_content(content) if json

        content
      rescue JSON::ParserError => e
        if json && retry_count < 3
          retry_count += 1
          warn "Retrying JSON response parse (#{retry_count}/3): #{e.message}"
          sleep retry_count
          retry
        end

        warn "Bad JSON received: #{content}"
        raise e
      rescue Faraday::BadRequestError => e
        warn "Chat completion failed: #{e.response&.dig(:body) || e.message}"
        raise e
      end
    end

    # Transcript array for this conversation.
    def transcript
      @transcript ||= TranscriptStore.new
    end

    # Dispatches a tool function call. Override for custom behavior.
    def dispatch_tool_function(function_name, arguments, cache: nil)
      public_send(function_name, arguments, cache)
    end

    private

    def runtime_client
      @runtime_client ||= Runtime::Client.new(configuration:)
    end

    def build_request_params(params, available_tools:)
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

      params
    end

    def apply_json_mode_params(params, json:, openai:)
      return params unless json

      unless openai
        params[:provider] ||= {}
        params[:provider][:require_parameters] = true
      end
      if params[:response_format].blank?
        params[:response_format] ||= {}
        params[:response_format][:type] = "json_object"
      end
      params
    end

    def warn_deprecated_loop(loop)
      return unless loop

      warn "\n\nWARNING: The 'loop' parameter is DEPRECATED and will be ignored.\nChat completions now automatically continue after tool calls until the AI provides a text response.\nUse 'max_tool_calls' to limit the number of tool calls (default: #{configuration.max_tool_calls}).\n\n"
    end

    def handle_tool_calls(tool_calls:, tool_call_count:, params:, json:, raw:, openai:, save_response:, available_tools:)
      if tool_call_count > max_tool_calls
        messages = transcript.flatten.compact.map { |msg| MessageAdapters::Base.new(self).transform(msg) }
        messages << { role: "system", content: "Maximum tool calls (#{max_tool_calls}) exceeded. Please provide a final response to the user without calling any more tools." }
        params[:tools] = nil

        final_response = execute_runtime_request(params:, model: openai || model, messages:, openai_override: openai)
        content = final_response.dig("choices", 0, "message", "content")
        transcript << { assistant: content } if save_response
        return raw ? final_response : content.to_s.strip
      end

      tool_calls.each do |tool_call|
        function_name = tool_call.dig("function", "name")
        arguments = JSON.parse(tool_call.dig("function", "arguments").presence || "{}")

        declared = Array(self.class.functions).map { |f| f[:name].to_sym }
        raise "Unauthorized function call: #{function_name}" unless declared.include?(function_name.to_sym)

        dispatch_tool_function(function_name, arguments.with_indifferent_access)
      end

      updated_messages = transcript.flatten.compact
      last_message = updated_messages.last

      if !@stop_tool_calls_and_respond && (last_message[:role] != "assistant" || last_message[:tool_calls].present?)
        return chat_completion(
          params:,
          json:,
          raw:,
          openai:,
          save_response:,
          messages: nil,
          available_tools:,
          max_tool_calls: max_tool_calls - tool_call_count
        )
      end

      return unless @stop_tool_calls_and_respond

      continuation_messages = updated_messages.map { |msg| MessageAdapters::Base.new(self).transform(msg) }
      params[:tools] = nil
      final_response = execute_runtime_request(params:, model: openai || model, messages: continuation_messages, openai_override: openai)
      content = final_response.dig("choices", 0, "message", "content")
      transcript << { assistant: content } if save_response
      raw ? final_response : content.to_s.strip
    end

    def parse_json_response_content(content)
      extracted = content
      if extracted.include?("<json>")
        match = extracted.match(%r{<json>(.*?)</json>}m)
        extracted = match[1] if match
      end

      JSON.parse(extracted)
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

      context = CompletionContext.new(chat_completion: self, messages:, params:)

      hooks.each do |hook|
        result = hook.call(context) if hook.respond_to?(:call)
        next unless result.is_a?(Hash)

        self.model = result[:model] if result.key?(:model)
        params.merge!(result.compact)
      end
    end

    def execute_runtime_request(params:, model:, messages:, openai_override:)
      runtime_client.complete(
        model:,
        messages:,
        params: params.compact,
        stream:,
        openai_override:
      )
    rescue Runtime::Error => e
      warn e.message
      raise e
    end
  end
end
