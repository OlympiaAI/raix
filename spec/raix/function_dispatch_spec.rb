# frozen_string_literal: true

class WhatIsTheWeather
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :check_weather, "Check the weather for a location", location: { type: "string" } do |arguments|
    "The weather in #{arguments[:location]} is hot and sunny"
  end

  def initialize
    self.seed = 9999
    transcript << { user: "What is the weather in Zipolite, Oaxaca?" }
  end
end

RSpec.describe WhatIsTheWeather do
  subject { described_class.new }

  it "can call a function and loop to provide text response" do
    response = subject.chat_completion(openai: "gpt-4o", loop: true)
    expect(response).to include("hot and sunny")
  end
end
