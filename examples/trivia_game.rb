#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv"
require "raix"

# Load environment variables from .env file
Dotenv.load

# Configure Raix with API keys
Raix.configure do |config|
  config.openrouter_api_key = ENV.fetch("OR_ACCESS_TOKEN", nil)
  config.openai_api_key = ENV.fetch("OAI_ACCESS_TOKEN", nil)
end

module Examples
  # A trivia game that uses AI to answer true/false questions
  class TriviaGame
    include Raix::Predicate

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.3
    end

    attr_reader :score, :questions_asked

    def initialize
      @score = 0
      @questions_asked = 0
    end

    # Define what happens when the answer is "yes"
    yes? do |response|
      @questions_asked += 1
      puts "\n✓ CORRECT! #{response.sub(/^yes,\s*/i, "")}"
      @score += 1
    end

    # Define what happens when the answer is "no"
    no? do |response|
      @questions_asked += 1
      puts "\n✗ INCORRECT! #{response.sub(/^no,\s*/i, "")}"
    end

    # Define what happens when the answer is "maybe"
    maybe? do |response|
      @questions_asked += 1
      puts "\n? UNCLEAR! #{response.sub(/^maybe,\s*/i, "")}"
    end

    def play(questions)
      puts "🎮 Welcome to AI Trivia Game!"
      puts "=" * 50

      questions.each_with_index do |question, index|
        puts "\nQuestion #{index + 1}: #{question}"
        print "Your answer (true/false): "
        user_answer = $stdin.gets.chomp.downcase

        # Convert user's answer to a question for the AI
        ai_question = "Is this statement true or false: #{question}. The user answered '#{user_answer}'. Is the user correct?"

        ask(ai_question)
      end

      show_results
    end

    def show_results
      puts "\n#{"=" * 50}"
      puts "🏆 Final Score: #{score}/#{questions_asked}"
      percentage = (score.to_f / questions_asked * 100).round
      puts "📊 Percentage: #{percentage}%"

      case percentage
      when 90..100
        puts "🌟 Outstanding! You're a trivia master!"
      when 70..89
        puts "😊 Great job! Keep it up!"
      when 50..69
        puts "🤔 Not bad! Room for improvement."
      else
        puts "📚 Better luck next time!"
      end
    end

    def self.run!(questions: nil)
      questions ||= default_questions
      new.play(questions)
    end

    def self.default_questions
      [
        "Ruby was created by Yukihiro Matsumoto",
        "Python was released before Ruby",
        "The Ruby programming language is named after the gemstone",
        "Rails was created in 2004",
        "Ruby uses curly braces for blocks exclusively"
      ]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  # You can provide custom questions or use the defaults
  if ARGV.any?
    Examples::TriviaGame.run!(questions: ARGV)
  else
    Examples::TriviaGame.run!
  end
end
