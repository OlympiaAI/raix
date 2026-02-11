# frozen_string_literal: true

RSpec.describe "before_completion hook" do
  # Helper to create a mock response hash that chat_completion expects
  def mock_response(content = "test response")
    {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => content,
            "tool_calls" => nil
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => {
        "prompt_tokens" => 10,
        "completion_tokens" => 5,
        "total_tokens" => 15
      }
    }
  end

  # Clean up global configuration after each test
  after do
    Raix.configuration.instance_variable_set(:@before_completion, nil)
  end

  describe "global-level before_completion hook" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "base-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "allows setting a before_completion hook at global level" do
      hook = ->(_context) { { model: "global-model" } }
      Raix.configure { |c| c.before_completion = hook }

      expect(Raix.configuration.before_completion).to eq(hook)
    end

    it "calls the hook and merges returned params" do
      hook_called = false
      Raix.configure do |c|
        c.before_completion = lambda { |_context|
          hook_called = true
          { temperature: 0.42 }
        }
      end

      instance = chat_class.new
      allow(instance).to receive(:execute_runtime_request).and_return(mock_response)

      instance.chat_completion

      expect(hook_called).to be true
    end
  end

  describe "class-level before_completion hook" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        configure do |c|
          c.before_completion = ->(_context) { { temperature: 0.9 } }
        end

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "allows setting a before_completion hook at class level" do
      expect(chat_class.configuration.before_completion).to be_a(Proc)
    end

    it "calls the class-level hook" do
      instance = chat_class.new
      allow(instance).to receive(:execute_runtime_request).and_return(mock_response)

      expect(instance.chat_completion).to eq("test response")
    end
  end

  describe "instance-level before_completion hook" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "allows setting a before_completion hook at instance level" do
      instance = chat_class.new
      hook = ->(_context) { { temperature: 0.5 } }
      instance.before_completion = hook

      expect(instance.before_completion).to eq(hook)
    end

    it "calls the instance-level hook" do
      instance = chat_class.new
      instance.before_completion = ->(_context) { { temperature: 0.5 } }
      allow(instance).to receive(:execute_runtime_request).and_return(mock_response)

      expect(instance.chat_completion).to eq("test response")
    end
  end

  describe "hook merge order" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        configure do |c|
          c.before_completion = ->(_context) { { temperature: 0.5, max_tokens: 500 } }
        end

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "merges hooks in order: global -> class -> instance (later overrides earlier)" do
      # Set up hooks at all three levels
      Raix.configure do |c|
        c.before_completion = ->(_context) { { temperature: 0.1, seed: 100 } }
      end

      instance = chat_class.new
      instance.before_completion = ->(_context) { { temperature: 0.9 } }

      # Track what params are passed via a spy
      params_received = nil
      allow(instance).to receive(:execute_runtime_request) do |args|
        params_received = args[:params]
        mock_response
      end

      instance.chat_completion

      # Instance hook (0.9) should override class hook (0.5) which overrides global (0.1)
      expect(params_received[:temperature]).to eq(0.9)
      # Class hook max_tokens should be present
      expect(params_received[:max_tokens]).to eq(500)
      # Global hook seed should be present
      expect(params_received[:seed]).to eq(100)
    end
  end

  describe "hook context object" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "passes a CompletionContext with correct data" do
      context_received = nil

      Raix.configure do |c|
        c.before_completion = lambda { |context|
          context_received = context
          {}
        }
      end

      instance = chat_class.new
      allow(instance).to receive(:execute_runtime_request).and_return(mock_response)

      instance.chat_completion

      expect(context_received).to be_a(Raix::CompletionContext)
      expect(context_received.chat_completion).to eq(instance)
      expect(context_received.messages).to be_an(Array)
      expect(context_received.params).to be_a(Hash)
      expect(context_received.current_model).to eq("test-model")
    end

    it "receives transformed messages in OpenAI format" do
      context_received = nil

      Raix.configure do |c|
        c.before_completion = lambda { |context|
          context_received = context
          {}
        }
      end

      instance = chat_class.new
      allow(instance).to receive(:execute_runtime_request).and_return(mock_response)

      instance.chat_completion

      # Messages should be in OpenAI format (transformed), not abbreviated format
      expect(context_received.messages.first).to have_key(:role)
      expect(context_received.messages.first).to have_key(:content)
      expect(context_received.messages.first[:role]).to eq("user")
    end
  end

  describe "hook returning nil" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "skips hooks that return nil" do
      Raix.configure do |c|
        c.before_completion = ->(_context) {}
      end

      instance = chat_class.new
      allow(instance).to receive(:execute_runtime_request).and_return(mock_response)

      # Should not raise an error
      expect { instance.chat_completion }.not_to raise_error
    end
  end

  describe "hook returning non-hash" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "skips hooks that return non-hash values" do
      Raix.configure do |c|
        c.before_completion = ->(_context) { "not a hash" }
      end

      instance = chat_class.new
      allow(instance).to receive(:execute_runtime_request).and_return(mock_response)

      # Should not raise an error
      expect { instance.chat_completion }.not_to raise_error
    end
  end

  describe "hook with callable object" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "works with any object that responds to #call" do
      hook_class = Class.new do
        def call(_context)
          { temperature: 0.42 }
        end
      end

      params_received = nil

      instance = chat_class.new
      instance.before_completion = hook_class.new

      allow(instance).to receive(:execute_runtime_request) do |args|
        params_received = args[:params]
        mock_response
      end

      instance.chat_completion

      expect(params_received[:temperature]).to eq(0.42)
    end
  end

  describe "hook can override any parameter" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "can override model" do
      params_received = nil

      instance = chat_class.new
      instance.before_completion = ->(_context) { { model: "different-model" } }

      allow(instance).to receive(:execute_runtime_request) do |args|
        params_received = args
        mock_response
      end

      instance.chat_completion

      # Model is passed separately in execute_runtime_request
      expect(params_received[:model]).to eq("different-model")
    end

    it "can override multiple parameters at once" do
      params_received = nil

      instance = chat_class.new
      instance.before_completion = lambda { |_context|
        {
          temperature: 0.8,
          max_tokens: 2000,
          frequency_penalty: 0.5,
          presence_penalty: 0.3,
          top_p: 0.95
        }
      }

      allow(instance).to receive(:execute_runtime_request) do |args|
        params_received = args[:params]
        mock_response
      end

      instance.chat_completion

      expect(params_received[:temperature]).to eq(0.8)
      expect(params_received[:max_tokens]).to eq(2000)
      expect(params_received[:frequency_penalty]).to eq(0.5)
      expect(params_received[:presence_penalty]).to eq(0.3)
      expect(params_received[:top_p]).to eq(0.95)
    end
  end

  describe "message mutation" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "My SSN is 123-45-6789" }
        end
      end
    end

    it "allows hooks to redact PII from messages" do
      messages_sent = nil

      instance = chat_class.new
      instance.before_completion = lambda { |context|
        # Redact SSN pattern from all messages
        context.messages.each do |msg|
          if msg[:content].is_a?(String)
            msg[:content] = msg[:content].gsub(/\d{3}-\d{2}-\d{4}/, "[SSN REDACTED]")
          end
        end
        {}
      }

      allow(instance).to receive(:execute_runtime_request) do |args|
        messages_sent = args[:messages]
        mock_response
      end

      instance.chat_completion

      expect(messages_sent.first[:content]).to eq("My SSN is [SSN REDACTED]")
    end

    it "allows hooks to add messages" do
      messages_sent = nil

      instance = chat_class.new
      instance.before_completion = lambda { |context|
        context.messages.unshift({ role: "system", content: "Be helpful" })
        {}
      }

      allow(instance).to receive(:execute_runtime_request) do |args|
        messages_sent = args[:messages]
        mock_response
      end

      instance.chat_completion

      expect(messages_sent.length).to eq(2)
      expect(messages_sent.first[:role]).to eq("system")
      expect(messages_sent.first[:content]).to eq("Be helpful")
    end

    it "allows hooks to filter/remove messages" do
      messages_sent = nil

      instance = chat_class.new
      instance.transcript << { assistant: "I can help with that" }
      instance.transcript << { user: "Thanks!" }

      instance.before_completion = lambda { |context|
        # Keep only the last user message
        context.messages.replace([context.messages.last])
        {}
      }

      allow(instance).to receive(:execute_runtime_request) do |args|
        messages_sent = args[:messages]
        mock_response
      end

      instance.chat_completion

      expect(messages_sent.length).to eq(1)
      expect(messages_sent.first[:content]).to eq("Thanks!")
    end
  end

  describe "logging use case" do
    let(:chat_class) do
      Class.new do
        include Raix::ChatCompletion

        def initialize
          self.model = "test-model"
          transcript << { user: "Hello" }
        end
      end
    end

    it "can be used for logging requests" do
      logged_data = nil

      instance = chat_class.new
      instance.before_completion = lambda { |context|
        logged_data = {
          model: context.current_model,
          message_count: context.messages.length,
          params: context.params.dup
        }
        {} # Return empty hash, just logging
      }

      allow(instance).to receive(:execute_runtime_request).and_return(mock_response)

      instance.chat_completion

      expect(logged_data[:model]).to eq("test-model")
      expect(logged_data[:message_count]).to eq(1)
      expect(logged_data[:params]).to include(:temperature)
    end
  end
end
