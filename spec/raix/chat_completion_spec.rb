# frozen_string_literal: true

class MeaningOfLife
  include Raix::ChatCompletion

  def initialize
    self.model = "meta-llama/llama-3-8b-instruct:free"
    self.seed = 9999 # try to get reproduceable results
    transcript << { user: "What is the meaning of life?" }
  end
end

class TestClassLevelConfiguration
  include Raix::ChatCompletion

  configure do |config|
    config.model = "drama-llama"
  end

  def initialize
    transcript << { user: "What is the meaning of life?" }
  end
end

RSpec.describe MeaningOfLife, :vcr do
  subject { described_class.new }

  it "does a completion with OpenAI" do
    expect(subject.chat_completion(openai: "gpt-4o")).to include("meaning of life is")
  end

  it "does a completion with OpenRouter" do
    expect(subject.chat_completion).to include("meaning of life is")
  end

  it "accepts a messages parameter to override the transcript" do
    expect(subject.chat_completion(openai: "gpt-4.1-nano", messages: [{ user: "What is the meaning of life?" }])).to include("meaning of life is")
  end

  context "with predicted outputs" do
    let(:completion) { subject.chat_completion(openai: "gpt-4o", params: { prediction: }) }
    let(:prediction) do
      "THE MEANING OF LIFE CAN VARY GREATLY FROM PERSON TO PERSON, OFTEN INVOLVING THE PURSUIT OF HAPPINESS, CARE OF OTHERS, AND PERSONAL GROWTH!."
    end
    let(:response) { Thread.current[:chat_completion_response] }

    before do
      subject.transcript.clear
      subject.transcript << { system: "Answer the user question in ALL CAPS." }
      subject.transcript << { user: "WHAT IS THE MEANING OF LIFE?" }
    end

    it "does a completion with OpenAI" do
      expect(completion).to start_with("THE MEANING OF LIFE")
      expect(subject.transcript.last).to eq({ assistant: completion })
      expect(response.dig("usage", "completion_tokens_details", "accepted_prediction_tokens")).to be > 0
      expect(response.dig("usage", "completion_tokens_details", "rejected_prediction_tokens")).to be > 0
    end
  end
end


RSpec.describe TestClassLevelConfiguration do
  it 'calls the open router gem with the correct model' do
    expect(Raix.configuration.openrouter_client).to receive(:complete) do |_messages, params|
      expect(params[:model]).to eq("drama-llama")
    end.and_return({'choices' =>  [{'message' =>  {'content' => "The meaning of life is to find your own meaning."}}]})
    subject.chat_completion
  end
end
