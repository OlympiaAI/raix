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
  # An AI-powered code reviewer that answers yes/no questions about code quality
  class CodeReviewer
    include Raix::Predicate

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.2
    end

    attr_reader :approved_count, :rejected_count, :unclear_count

    def initialize
      @approved_count = 0
      @rejected_count = 0
      @unclear_count = 0
    end

    # When the code passes review
    yes? do |response|
      @approved_count += 1
      puts "✅ APPROVED"
      puts "   #{response.sub(/^yes,\s*/i, "").strip}"
      puts
    end

    # When the code fails review
    no? do |response|
      @rejected_count += 1
      puts "❌ REJECTED"
      puts "   #{response.sub(/^no,\s*/i, "").strip}"
      puts
    end

    # When the answer is unclear
    maybe? do |response|
      @unclear_count += 1
      puts "⚠️  NEEDS REVIEW"
      puts "   #{response.sub(/^maybe,\s*/i, "").strip}"
      puts
    end

    def review_code(code, question = nil)
      question ||= "Is this code following Ruby best practices and free of obvious issues?"
      full_question = "#{question}\n\nCode:\n```ruby\n#{code}\n```"

      puts "🔍 Reviewing code..."
      puts "-" * 60
      ask(full_question)
    end

    def summary
      total = approved_count + rejected_count + unclear_count
      return if total.zero?

      puts "=" * 60
      puts "📊 Review Summary:"
      puts "   ✅ Approved: #{approved_count}"
      puts "   ❌ Rejected: #{rejected_count}"
      puts "   ⚠️  Unclear:  #{unclear_count}"
      puts "   📝 Total:    #{total}"
    end

    def self.run!
      reviewer = new

      puts "🤖 AI Code Reviewer Demo"
      puts "=" * 60
      puts

      # Example 1: Good code
      puts "Example 1: Clean Ruby code"
      reviewer.review_code(<<~RUBY)
        def calculate_total(items)
          items.sum(&:price)
        end
      RUBY

      # Example 2: Code with issues
      puts "Example 2: Code with potential issues"
      reviewer.review_code(<<~RUBY)
        def calc(x)
          sum = 0
          for i in 0..x.length-1
            sum = sum + x[i]
          end
          return sum
        end
      RUBY

      # Example 3: Complex case
      puts "Example 3: Code that might be ambiguous"
      reviewer.review_code(<<~RUBY, "Does this code properly handle nil values?")
        def process_user(user)
          user.name.upcase
        end
      RUBY

      reviewer.summary
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Examples::CodeReviewer.run!
end
