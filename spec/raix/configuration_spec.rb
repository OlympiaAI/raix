RSpec.describe Raix::Configuration do
  describe "#client?" do
    context "with an openrouter_client" do
      it "returns true" do
        configuration = Raix::Configuration.new
        configuration.openrouter_client = OpenRouter::Client.new
        expect(configuration.client?).to eq true
      end
    end

    context "with an openai_client" do
      it "returns true" do
        configuration = Raix::Configuration.new
        configuration.openai_client = OpenAI::Client.new
        expect(configuration.client?).to eq true
      end
    end

    context "without an api client" do
      it "returns false" do
        configuration = Raix::Configuration.new
        expect(configuration.client?).to eq false
      end
    end

    context "with a fallback with openai_client" do
      it "returns true" do
        configuration = Raix::Configuration.new
        configuration.openrouter_client = OpenRouter::Client.new
        child_config = Raix::Configuration.new(fallback: configuration)

        expect(child_config.client?).to be true
      end
    end

    context "with a fallback with openrouter_client" do
      it "returns true" do
        configuration = Raix::Configuration.new
        configuration.openai_client = OpenAI::Client.new
        child_config = Raix::Configuration.new(fallback: configuration)

        expect(child_config.client?).to be true
      end
    end

    context "with a fallback with neither client" do
      it "returns false" do
        configuration = Raix::Configuration.new
        child_config = Raix::Configuration.new(fallback: configuration)

        expect(child_config.client?).to be false
      end
    end
  end

  describe "registering providers" do
    it "allows registering a provider with a name and client" do
      configuration = Raix::Configuration.new
      mock_client = double("MockClient")

      configuration.register_provider(:test_provider, mock_client)

      expect(configuration.providers[:test_provider]).to eq(mock_client)
    end

    it "allows retrieving a registered provider" do
      configuration = Raix::Configuration.new
      mock_client = double("MockClient")

      configuration.register_provider(:test_provider, mock_client)

      expect(configuration.provider(:test_provider)).to eq(mock_client)
    end

    it "returns nil for unregistered providers" do
      configuration = Raix::Configuration.new

      expect(configuration.provider(:unknown)).to be_nil
    end

    it "considers registered providers in client? check" do
      configuration = Raix::Configuration.new
      mock_client = double("MockClient")

      expect(configuration.client?).to be false

      configuration.register_provider(:test_provider, mock_client)

      expect(configuration.client?).to be true
    end
  end

  describe "internal provider storage" do
    it "stores openai_client in the provider registry" do
      configuration = Raix::Configuration.new
      openai_client = double("OpenAI Client")

      configuration.openai_client = openai_client

      expect(configuration.provider(:openai)).to be_a(Raix::Providers::OpenAIProvider)
      expect(configuration.provider(:openai).client).to eq(openai_client)
      expect(configuration.openai_client).to eq(openai_client)
    end

    it "stores openrouter_client in the provider registry" do
      configuration = Raix::Configuration.new
      openrouter_client = double("OpenRouter Client")

      configuration.openrouter_client = openrouter_client

      expect(configuration.provider(:openrouter)).to be_a(Raix::Providers::OpenRouterProvider)
      expect(configuration.provider(:openrouter).client).to eq(openrouter_client)
      expect(configuration.openrouter_client).to eq(openrouter_client)
    end

    it "returns nil for provider when client is not set" do
      configuration = Raix::Configuration.new

      expect(configuration.provider(:openai)).to be_nil
      expect(configuration.provider(:openrouter)).to be_nil
    end
  end

  describe "#provider" do
    let(:configuration) { Raix::Configuration.new }

    context "when a specific provider name is requested" do
      context "and the provider is registered" do
        it "returns the registered provider" do
          mock_provider = double("MockProvider")
          configuration.register_provider(:custom, mock_provider)

          expect(configuration.provider(:custom)).to eq(mock_provider)
        end
      end

      context "and the provider is not registered" do
        context "when requesting :openai" do
          it "returns OpenAIProvider if openai_client is set" do
            openai_client = double("OpenAI Client")
            configuration.openai_client = openai_client

            provider = configuration.provider(:openai)
            expect(provider).to be_a(Raix::Providers::OpenAIProvider)
            expect(provider.client).to eq(openai_client)
          end

          it "returns nil if openai_client is not set" do
            expect(configuration.provider(:openai)).to be_nil
          end
        end

        context "when requesting :openrouter" do
          it "returns OpenRouterProvider if openrouter_client is set" do
            openrouter_client = double("OpenRouter Client")
            configuration.openrouter_client = openrouter_client

            provider = configuration.provider(:openrouter)
            expect(provider).to be_a(Raix::Providers::OpenRouterProvider)
            expect(provider.client).to eq(openrouter_client)
          end

          it "returns nil if openrouter_client is not set" do
            expect(configuration.provider(:openrouter)).to be_nil
          end
        end

        context "when requesting an unknown provider" do
          it "returns nil" do
            expect(configuration.provider(:unknown)).to be_nil
          end
        end
      end
    end

    context "when no provider name is specified" do
      context "and openrouter_client is set" do
        it "returns OpenRouterProvider for backwards compatibility" do
          openrouter_client = double("OpenRouter Client")
          configuration.openrouter_client = openrouter_client

          provider = configuration.provider
          expect(provider).to be_a(Raix::Providers::OpenRouterProvider)
          expect(provider.client).to eq(openrouter_client)
        end

        it "prioritizes openrouter_client even if providers are registered" do
          openrouter_client = double("OpenRouter Client")
          configuration.openrouter_client = openrouter_client
          configuration.register_provider(:custom, double("CustomProvider"))

          provider = configuration.provider
          expect(provider).to be_a(Raix::Providers::OpenRouterProvider)
        end
      end

      context "and openrouter_client is not set but providers are registered" do
        it "returns the first registered provider" do
          first_provider = double("FirstProvider")
          second_provider = double("SecondProvider")

          configuration.register_provider(:first, first_provider)
          configuration.register_provider(:second, second_provider)

          expect(configuration.provider).to eq(first_provider)
        end
      end

      context "and no clients or providers are set" do
        context "with a fallback configuration" do
          let(:fallback) { Raix::Configuration.new }
          let(:configuration) { Raix::Configuration.new(fallback:) }

          it "delegates to fallback's provider method" do
            mock_provider = double("MockProvider")
            fallback.register_provider(:fallback_provider, mock_provider)

            expect(configuration.provider).to eq(mock_provider)
          end

          it "passes the name parameter to fallback" do
            mock_provider = double("MockProvider")
            fallback.register_provider(:custom, mock_provider)

            expect(configuration.provider(:custom)).to eq(mock_provider)
          end
        end

        context "without a fallback configuration" do
          it "returns nil" do
            expect(configuration.provider).to be_nil
          end
        end
      end
    end

    context "priority order verification" do
      it "prioritizes registered providers over openai_client" do
        mock_provider = double("MockProvider")
        openai_client = double("OpenAI Client")

        configuration.openai_client = openai_client
        configuration.register_provider(:openai, mock_provider)

        expect(configuration.provider(:openai)).to eq(mock_provider)
      end

      it "prioritizes registered providers over openrouter_client" do
        mock_provider = double("MockProvider")
        openrouter_client = double("OpenRouter Client")

        configuration.openrouter_client = openrouter_client
        configuration.register_provider(:openrouter, mock_provider)

        expect(configuration.provider(:openrouter)).to eq(mock_provider)
      end
    end
  end

  describe "fallback behavior with provider registry" do
    it "falls back to parent openai_client when not set" do
      fallback = Raix::Configuration.new
      openai_client = double("OpenAI Client")
      fallback.openai_client = openai_client

      configuration = Raix::Configuration.new(fallback:)

      expect(configuration.openai_client).to eq(openai_client)
      expect(configuration.provider(:openai).client).to eq(openai_client)
    end

    it "falls back to parent openrouter_client when not set" do
      fallback = Raix::Configuration.new
      openrouter_client = double("OpenRouter Client")
      fallback.openrouter_client = openrouter_client

      configuration = Raix::Configuration.new(fallback:)

      expect(configuration.openrouter_client).to eq(openrouter_client)
      expect(configuration.provider(:openrouter).client).to eq(openrouter_client)
    end

    it "uses local openai_client when set, ignoring parent" do
      fallback = Raix::Configuration.new
      openai_client = double("OpenAI Client")
      fallback.openai_client = openai_client

      configuration = Raix::Configuration.new(fallback:)
      local_openai_client = double("Local OpenAI Client")
      configuration.openai_client = local_openai_client

      expect(configuration.openai_client).to eq(local_openai_client)
      expect(configuration.provider(:openai).client).to eq(local_openai_client)
    end
  end
end
