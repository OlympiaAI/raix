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
  end
end
