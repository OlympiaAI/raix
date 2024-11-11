# frozen_string_literal: true

require "raix/predicate"

class Question
  include Raix::Predicate

  yes? do |explanation|
    @callback.call(:yes, explanation)
  end

  no? do |explanation|
    @callback.call(:no, explanation)
  end

  maybe? do |explanation|
    @callback.call(:maybe, explanation)
  end

  def initialize(callback)
    @callback = callback
  end
end

class QuestionWithNoBlocks
  include Raix::Predicate
end

RSpec.describe Raix::Predicate, :vcr do
  let(:callback) { double("callback") }
  let(:question) { Question.new(callback) }

  it "yes" do
    expect(callback).to receive(:call).with(:yes, "Yes, Ruby on Rails is a web application framework.")
    question.ask("Is Ruby on Rails a web application framework?")
  end

  it "no" do
    expect(callback).to receive(:call).with(:no, "No, the Eiffel Tower is located in Paris, France, not Madrid, Spain.")
    question.ask("Is the Eiffel Tower in Madrid?")
  end

  it "maybe" do
    expect(callback).to receive(:call).with(:maybe, "Maybe, it depends on the specific situation and context.")
    question.ask("Should I quit my job?")
  end

  it "raises an error if no blocks are defined" do
    expect { QuestionWithNoBlocks.new.ask("Is Ruby on Rails a web application framework?") }.to raise_error(RuntimeError, "Please define a yes and/or no block")
  end
end
