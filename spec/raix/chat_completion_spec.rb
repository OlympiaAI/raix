# frozen_string_literal: true

class MeaningOfLife
  include Raix::ChatCompletion

  def initialize
    self.model = "meta-llama/llama-3-8b-instruct:free"
    self.seed = 9999 # try to get reproduceable results
    transcript << { user: "What is the meaning of life?" }
  end
end

RSpec.describe MeaningOfLife do
  subject { described_class.new }

  it "does a completion with OpenAI" do
    expect(subject.chat_completion(openai: "gpt-4o")).to include("meaning of life is")
  end

  it "does a completion with OpenRouter" do
    expect(subject.chat_completion).to include("meaning of life is")
  end
end
