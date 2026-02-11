#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv"
require "json"
require "raix"

# Load environment variables from .env file
Dotenv.load

# Configure Raix with API keys
Raix.configure do |config|
  config.openrouter_api_key = ENV.fetch("OR_ACCESS_TOKEN", nil)
  config.openai_api_key = ENV.fetch("OAI_ACCESS_TOKEN", nil)
end

module Examples
  # Demonstrates JSON mode for getting flexible structured responses without
  # strict schema validation. Unlike ResponseFormat, JSON mode lets the AI
  # determine the structure while ensuring valid JSON output.
  class JsonModeDemo
    include Raix::ChatCompletion

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.3
    end

    # Analyze text sentiment with flexible JSON response
    def analyze_sentiment(text)
      puts "📝 Text to Analyze:"
      puts text
      puts "\n" + "-" * 60

      transcript << {
        system: "You are a sentiment analysis expert. Return your analysis as JSON."
      }
      transcript << {
        user: <<~PROMPT
          Analyze the sentiment of this text and return a JSON object with:
          - overall_sentiment (positive/negative/neutral/mixed)
          - confidence_score (0-1)
          - key_emotions (array)
          - summary (brief explanation)

          Text: #{text}
        PROMPT
      }

      puts "🔍 Analyzing sentiment...\n\n"
      result = chat_completion(json: true)

      puts "✅ Analysis Result:"
      puts JSON.pretty_generate(result)
      puts

      result
    end

    # Compare items and return flexible comparison data
    def compare_items(item1, item2, criteria)
      puts "⚖️  Comparing: #{item1} vs #{item2}"
      puts "Criteria: #{criteria.join(', ')}"
      puts "\n" + "-" * 60

      transcript << {
        system: "You are a comparison expert. Return detailed comparisons as JSON."
      }
      transcript << {
        user: <<~PROMPT
          Compare #{item1} and #{item2} based on these criteria: #{criteria.join(', ')}.

          Return a JSON object with:
          - winner (which is better overall)
          - comparison (object with each criterion as a key, containing scores and notes)
          - recommendation (who should choose which option)
        PROMPT
      }

      puts "🔍 Comparing...\n\n"
      result = chat_completion(json: true)

      puts "✅ Comparison Result:"
      puts JSON.pretty_generate(result)
      puts

      result
    end

    # Generate a quiz with flexible structure
    def generate_quiz(topic, num_questions)
      puts "📚 Generating Quiz on: #{topic}"
      puts "Number of questions: #{num_questions}"
      puts "\n" + "-" * 60

      transcript << {
        system: "You create educational quizzes. Return quiz data as JSON."
      }
      transcript << {
        user: <<~PROMPT
          Create a #{num_questions}-question quiz about #{topic}.

          Return JSON with:
          - title
          - questions (array of objects with question, options, correct_answer, explanation)
          - difficulty_level
        PROMPT
      }

      puts "🔍 Creating quiz...\n\n"
      result = chat_completion(json: true)

      puts "✅ Generated Quiz:"
      puts JSON.pretty_generate(result)
      puts

      result
    end

    # Recipe generation with flexible JSON structure
    def generate_recipe(dish, dietary_restrictions = [])
      puts "🍳 Generating Recipe for: #{dish}"
      puts "Dietary restrictions: #{dietary_restrictions.any? ? dietary_restrictions.join(', ') : 'None'}"
      puts "\n" + "-" * 60

      restrictions = dietary_restrictions.any? ? " (#{dietary_restrictions.join(', ')})" : ""

      transcript << {
        system: "You are a chef. Create recipes as structured JSON."
      }
      transcript << {
        user: <<~PROMPT
          Create a recipe for #{dish}#{restrictions}.

          Return JSON with whatever structure makes sense, but include:
          - name, description, servings, prep_time, cook_time
          - ingredients (with amounts)
          - instructions (step by step)
          - nutritional_info (if relevant)
          - tips
        PROMPT
      }

      puts "🔍 Creating recipe...\n\n"
      result = chat_completion(json: true)

      puts "✅ Generated Recipe:"
      puts JSON.pretty_generate(result)
      puts

      result
    end

    def self.run!
      demo = new

      puts "🎯 Raix JSON Mode Demo"
      puts "Flexible structured responses without strict schemas"
      puts "=" * 60
      puts "\nNote: JSON mode ensures valid JSON but lets the AI determine structure."
      puts "Compare with ResponseFormat which enforces a specific schema."
      puts "=" * 60
      puts

      # Example 1: Sentiment Analysis
      puts "Example 1: Sentiment Analysis"
      puts "=" * 60
      review = "I absolutely loved this product! The quality exceeded my expectations, "\
               "though I wish the shipping had been a bit faster. Overall, highly recommended!"
      demo.analyze_sentiment(review)

      puts "\n" + "=" * 60 + "\n\n"

      # Example 2: Item Comparison
      puts "Example 2: Product Comparison"
      puts "=" * 60
      demo.compare_items(
        "MacBook Pro",
        "Dell XPS 15",
        ["performance", "price", "portability", "ecosystem"]
      )

      puts "\n" + "=" * 60 + "\n\n"

      # Example 3: Quiz Generation
      puts "Example 3: Quiz Generation"
      puts "=" * 60
      demo.generate_quiz("Ruby Programming Basics", 3)

      puts "\n" + "=" * 60 + "\n\n"

      # Example 4: Recipe Generation
      puts "Example 4: Recipe Generation"
      puts "=" * 60
      demo.generate_recipe("Chocolate Chip Cookies", ["gluten-free"])

      puts "\n" + "=" * 60
      puts "✨ JSON mode demo complete!"
      puts "\n💡 Key Differences:"
      puts "   • JSON Mode: Flexible structure, AI decides format"
      puts "   • ResponseFormat: Strict schema, enforced validation"
      puts "   • Use JSON mode when you want structured data but flexibility in format"
      puts "   • Use ResponseFormat when you need exact schema compliance"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Examples::JsonModeDemo.run!
end
