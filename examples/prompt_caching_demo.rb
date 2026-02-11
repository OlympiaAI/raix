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
  # Demonstrates prompt caching to reduce costs when repeatedly using
  # large context (documents, character cards, knowledge bases).
  # Uses Anthropic's cache control feature.
  class PromptCachingDemo
    include Raix::ChatCompletion

    configure do |config|
      # Note: Caching works best with Anthropic models
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "anthropic/claude-3-5-sonnet")
      config.temperature = 0.5
    end

    # Large document to be cached (simulating a knowledge base)
    COMPANY_HANDBOOK = <<~HANDBOOK
      # Company Employee Handbook

      ## Introduction
      Welcome to TechCorp! This handbook contains essential information about our company
      policies, culture, and procedures. Please familiarize yourself with its contents.

      ## Company Values
      1. Innovation First: We encourage creative thinking and calculated risks
      2. Customer Success: Our customers' success is our success
      3. Collaborative Spirit: We work together to achieve great things
      4. Continuous Learning: We invest in our people's growth
      5. Work-Life Balance: We believe in sustainable productivity

      ## Work Policies

      ### Remote Work
      - Employees may work remotely up to 3 days per week
      - Core hours are 10 AM - 3 PM in your local timezone
      - Must be available for team meetings during core hours
      - Home office stipend: $500 annually

      ### Time Off
      - Vacation: 20 days per year, increasing to 25 after 3 years
      - Sick Leave: 10 days per year (unused days roll over)
      - Parental Leave: 16 weeks paid for primary caregiver
      - Holidays: 10 company holidays plus your birthday

      ### Professional Development
      - Conference Budget: $2,000 per year
      - Online Learning: Unlimited access to learning platforms
      - Mentorship Program: All employees can participate
      - Innovation Time: 10% of work time for personal projects

      ### Health & Wellness
      - Health Insurance: Comprehensive coverage, company pays 90%
      - Dental & Vision: Full coverage included
      - Mental Health: Unlimited therapy sessions
      - Gym Membership: $100/month reimbursement
      - Wellness Days: 4 additional days off per year

      ### Equipment & Tools
      - Laptop: Choose between Mac or PC, replaced every 3 years
      - Monitors: Up to 2 external monitors
      - Accessories: Keyboard, mouse, headphones covered
      - Software: Any tools needed for your role

      ## Code of Conduct
      - Treat all colleagues with respect and dignity
      - Embrace diversity and inclusion
      - Maintain confidentiality of sensitive information
      - Report concerns to HR immediately
      - No tolerance for harassment or discrimination

      ## Performance Reviews
      - Conducted quarterly with your manager
      - 360-degree feedback from peers
      - Clear goals and development plans
      - Compensation reviews annually

      ## Contact Information
      - HR: hr@techcorp.com
      - IT Support: support@techcorp.com
      - Facilities: facilities@techcorp.com
      - Emergency: Call security at ext. 911

      Last Updated: January 2024
      Version 3.2
    HANDBOOK

    def initialize
      setup_cached_context
    end

    # Setup the cached context (this part gets cached)
    def setup_cached_context
      # Add the large document with cache control
      transcript << {
        role: "system",
        content: [
          {
            type: "text",
            text: "You are TechCorp's HR assistant. Answer questions based on the employee handbook.",
            cache_control: { type: "ephemeral" }
          },
          {
            type: "text",
            text: COMPANY_HANDBOOK,
            cache_control: { type: "ephemeral" }
          }
        ]
      }
    end

    def ask_question(question)
      puts "❓ Question: #{question}"

      transcript << { user: question }

      start_time = Time.now
      response = chat_completion(params: { cache_at: 1000 })
      duration = (Time.now - start_time).round(2)

      puts "💬 Answer: #{response}"
      puts "⏱️  Response time: #{duration}s"
      puts

      response
    end

    def self.run!
      puts "💾 Raix Prompt Caching Demo"
      puts "Reducing costs with cached context"
      puts "=" * 60
      puts

      puts "📚 Context Size: #{COMPANY_HANDBOOK.split.length} words"
      puts "🎯 Model: Using Anthropic Claude (supports caching)"
      puts
      puts "Note: The first request will cache the handbook."
      puts "      Subsequent requests will use the cache (faster & cheaper)."
      puts "=" * 60
      puts

      assistant = new

      # First question - will cache the handbook
      puts "Request 1: Establishing cache"
      puts "-" * 60
      assistant.ask_question("How many vacation days do I get?")
      puts

      # Second question - should use cache
      puts "Request 2: Using cached context"
      puts "-" * 60
      assistant.ask_question("What is the remote work policy?")
      puts

      # Third question - should use cache
      puts "Request 3: Using cached context"
      puts "-" * 60
      assistant.ask_question("How much is the professional development budget?")
      puts

      # Fourth question - should use cache
      puts "Request 4: Using cached context"
      puts "-" * 60
      assistant.ask_question("What are the company values?")
      puts

      puts "=" * 60
      puts "✨ Caching demo complete!"
      puts
      puts "💡 How Prompt Caching Works:"
      puts "   • Large context (handbook) is cached after first request"
      puts "   • Subsequent requests reuse the cached context"
      puts "   • Only the new user message is processed"
      puts "   • Results in faster responses and lower costs"
      puts
      puts "💰 Cost Savings:"
      puts "   • First request: Full context processed (~1200 tokens)"
      puts "   • Cached requests: Only new message processed (~10-20 tokens)"
      puts "   • ~98% reduction in input token costs for follow-up questions"
      puts
      puts "⚡ Performance:"
      puts "   • Cached requests are typically 2-3x faster"
      puts "   • Cache is valid for 5 minutes (Anthropic)"
      puts "   • Perfect for: RAG, chatbots, document analysis"
    end
  end

  # Example showing caching with a character card (AI roleplaying)
  class CharacterCachingDemo
    include Raix::ChatCompletion

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "anthropic/claude-3-5-sonnet")
      config.temperature = 0.8
    end

    CHARACTER_CARD = <<~CARD
      # Character: Dr. Elena Rodriguez

      ## Background
      Dr. Elena Rodriguez is a brilliant astrophysicist in her mid-40s who works at
      the International Space Observatory. She has dedicated her life to studying
      exoplanets and the search for extraterrestrial life.

      ## Personality
      - Passionate and enthusiastic about space exploration
      - Patient teacher who loves explaining complex concepts
      - Slightly eccentric, often uses space metaphors
      - Optimistic about humanity's future among the stars
      - Has a dry sense of humor

      ## Speaking Style
      - Uses scientific terminology but explains things clearly
      - Often references astronomical phenomena in conversation
      - Speaks with quiet confidence and wonder
      - Makes space puns occasionally

      ## Knowledge Areas
      - Expert in exoplanet detection and characterization
      - Deep knowledge of stellar evolution
      - Understanding of astrobiology and habitability
      - Familiar with space mission design and technology

      ## Current Projects
      - Leading the TERRA-FIND mission to discover Earth-like planets
      - Developing new spectroscopic analysis techniques
      - Mentoring graduate students in astrophysics
    CARD

    def initialize
      transcript << {
        role: "system",
        content: [
          {
            type: "text",
            text: "You are roleplaying as this character. Stay in character and respond naturally.",
            cache_control: { type: "ephemeral" }
          },
          {
            type: "text",
            text: CHARACTER_CARD,
            cache_control: { type: "ephemeral" }
          }
        ]
      }
    end

    def chat(message)
      transcript << { user: message }
      chat_completion(params: { cache_at: 1000 })
    end

    def self.run!
      puts "\n\n" + "=" * 60
      puts "🎭 Character Caching Demo"
      puts "=" * 60
      puts

      character = new

      puts "Character: Dr. Elena Rodriguez (Astrophysicist)"
      puts "-" * 60
      puts

      conversation = [
        "Hello Dr. Rodriguez! What are you working on today?",
        "What's the most exciting exoplanet you've discovered?",
        "Do you think we'll find alien life in our lifetime?"
      ]

      conversation.each_with_index do |message, i|
        puts "You: #{message}"
        response = character.chat(message)
        puts "Dr. Rodriguez: #{response}"
        puts
      end

      puts "=" * 60
      puts "💡 Character Card Caching Benefits:"
      puts "   • Large character description cached once"
      puts "   • Consistent personality across conversation"
      puts "   • Lower costs for multi-turn conversations"
      puts "   • Perfect for AI roleplaying and chatbots"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  # Run both demos
  Examples::PromptCachingDemo.run!
  Examples::CharacterCachingDemo.run!
end
