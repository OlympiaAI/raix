# frozen_string_literal: true

RSpec.describe "nil content in final assistant response" do
  # Some providers (notably Gemini under certain stop conditions) return a final
  # assistant message with `content: nil`. The three call sites in chat_completion
  # that turn the response into a string previously crashed with NoMethodError on
  # `nil.strip`. They now use `content.to_s.strip` and should return "".

  def nil_content_response(tool_calls: nil)
    {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => tool_calls
          },
          "finish_reason" => tool_calls ? "tool_calls" : "stop"
        }
      ],
      "usage" => {
        "prompt_tokens" => 1,
        "completion_tokens" => 0,
        "total_tokens" => 1
      }
    }
  end

  def tool_call_response
    {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              {
                "id" => "call_1",
                "type" => "function",
                "function" => {
                  "name" => "do_thing",
                  "arguments" => "{}"
                }
              }
            ]
          },
          "finish_reason" => "tool_calls"
        }
      ],
      "usage" => {
        "prompt_tokens" => 1,
        "completion_tokens" => 0,
        "total_tokens" => 1
      }
    }
  end

  describe "plain final response with nil content" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "returns an empty string instead of raising NoMethodError" do
      instance = chat_class.new
      allow(instance).to receive(:ruby_llm_request).and_return(nil_content_response)

      expect { instance.chat_completion }.not_to raise_error
    end

    it "returns an empty string when content is nil" do
      instance = chat_class.new
      allow(instance).to receive(:ruby_llm_request).and_return(nil_content_response)

      expect(instance.chat_completion).to eq("")
    end
  end

  describe "max_tool_calls exceeded with nil content on forced final response" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion
        include Raix::FunctionDispatch

        function :do_thing, "Does a thing" do |_arguments|
          "done"
        end

        def initialize
          self.model = "test-model"
          transcript << { user: "Call do_thing repeatedly" }
        end
      end
    end

    it "returns an empty string instead of raising NoMethodError" do
      instance = chat_class.new

      # First call returns a tool call (which exceeds max_tool_calls=0),
      # forcing chat_completion into the max-tool-calls-exceeded branch.
      # The forced final response then returns nil content.
      call_count = 0
      allow(instance).to receive(:ruby_llm_request) do
        call_count += 1
        call_count == 1 ? tool_call_response : nil_content_response
      end

      expect { instance.chat_completion(max_tool_calls: 0) }.not_to raise_error
    end

    it "returns an empty string when forced final content is nil" do
      instance = chat_class.new

      call_count = 0
      allow(instance).to receive(:ruby_llm_request) do
        call_count += 1
        call_count == 1 ? tool_call_response : nil_content_response
      end

      expect(instance.chat_completion(max_tool_calls: 0)).to eq("")
    end
  end

  describe "stop_tool_calls_and_respond! with nil content on forced final response" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion
        include Raix::FunctionDispatch

        function :stop_now, "Halts and forces a final response" do |_arguments|
          stop_tool_calls_and_respond!
          "stopping"
        end

        def initialize
          self.model = "test-model"
          transcript << { user: "Call stop_now" }
        end
      end
    end

    it "returns an empty string instead of raising NoMethodError" do
      instance = chat_class.new

      stop_tool_call = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                {
                  "id" => "call_stop",
                  "type" => "function",
                  "function" => {
                    "name" => "stop_now",
                    "arguments" => "{}"
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ],
        "usage" => { "prompt_tokens" => 1, "completion_tokens" => 0, "total_tokens" => 1 }
      }

      call_count = 0
      allow(instance).to receive(:ruby_llm_request) do
        call_count += 1
        call_count == 1 ? stop_tool_call : nil_content_response
      end

      expect { instance.chat_completion }.not_to raise_error
    end
  end
end
