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
  # Demonstrates PromptDeclarations for building multi-step AI workflows
  # with conditional execution, callbacks, and looping.
  class PromptChainWorkflow
    include Raix::ChatCompletion
    include Raix::PromptDeclarations

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.7
    end

    attr_accessor :research_topic, :key_points, :outline_approved, :draft_sections

    def initialize(topic)
      @research_topic = topic
      @key_points = []
      @outline_approved = false
      @draft_sections = []
    end

    # Step 1: Initial research
    prompt text: lambda {
      "Research the topic '#{research_topic}' and identify 3-5 key points that should be covered. " \
        "List each point clearly."
    }, success: lambda { |response|
      puts "✅ Research complete"
      @key_points = response.split("\n").grep(/^\d+\./).map { |line| line.sub(/^\d+\.\s*/, "") }
      puts "   Found #{@key_points.length} key points"
      puts
    }

    # Step 2: Create outline (only if we have key points)
    prompt text: lambda {
      "Based on these key points:\n#{key_points.map.with_index { |p, i| "#{i + 1}. #{p}" }.join("\n")}\n\n" \
        "Create a detailed outline for an article about #{research_topic}."
    }, if: -> { key_points.any? }, success: lambda { |response|
      puts "✅ Outline created"
      puts "   Validating structure..."
      @outline_approved = response.include?("Introduction") || response.include?("Overview")
      puts "   Outline #{outline_approved ? "approved ✓" : "needs revision ✗"}"
      puts
    }

    # Step 3: Write introduction (only if outline approved)
    prompt text: lambda {
      "Write an engaging introduction for an article about #{research_topic}. " \
        "Keep it concise (2-3 paragraphs)."
    }, if: -> { outline_approved }, success: lambda { |response|
      puts "✅ Introduction written"
      @draft_sections << { section: "Introduction", content: response }
      puts "   Added to draft (#{draft_sections.length} sections)"
      puts
    }

    # Step 4: Write main content sections
    prompt text: lambda {
      "Write the main body section covering these key points:\n" \
        "#{key_points.map.with_index { |p, i| "#{i + 1}. #{p}" }.join("\n")}\n\n" \
        "Make it informative and well-structured."
    }, if: -> { draft_sections.any? }, success: lambda { |response|
      puts "✅ Main content written"
      @draft_sections << { section: "Main Content", content: response }
      puts "   Added to draft (#{draft_sections.length} sections)"
      puts
    }

    # Step 5: Write conclusion
    prompt text: lambda {
      "Write a conclusion that summarizes the key insights about #{research_topic} " \
        "and provides a forward-looking perspective."
    }, if: -> { draft_sections.length >= 2 }, success: lambda { |response|
      puts "✅ Conclusion written"
      @draft_sections << { section: "Conclusion", content: response }
      puts "   Added to draft (#{draft_sections.length} sections)"
      puts
    }

    def run!
      puts "📝 AI Research & Writing Workflow"
      puts "Topic: #{research_topic}"
      puts "=" * 60
      puts

      # Execute the prompt chain
      execute_prompt_chain

      # Display final article
      puts "\n#{"=" * 60}"
      puts "📄 Complete Article"
      puts "=" * 60
      puts

      draft_sections.each do |section|
        puts "### #{section[:section]}"
        puts
        puts section[:content]
        puts
        puts "-" * 60
        puts
      end

      puts "✨ Workflow complete!"
      puts "   Generated #{draft_sections.length} sections"
    end

    def self.run!(topic = nil)
      topic ||= ENV["RESEARCH_TOPIC"] || "The Future of AI in Education"
      new(topic).run!
    end
  end

  # Example 2: Data processing workflow with error handling
  class DataProcessingWorkflow
    include Raix::ChatCompletion
    include Raix::PromptDeclarations

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.3
    end

    attr_accessor :raw_data, :cleaned_data, :analysis_results, :retry_count

    def initialize(data)
      @raw_data = data
      @cleaned_data = nil
      @analysis_results = {}
      @retry_count = 0
    end

    # Step 1: Validate and clean data
    prompt text: lambda {
      "Analyze this data and identify any issues or inconsistencies:\n\n#{raw_data}\n\n" \
        "Return 'CLEAN' if data is valid, or describe the issues found."
    }, success: lambda { |response|
      if response.include?("CLEAN")
        @cleaned_data = raw_data
        puts "✅ Data validation passed"
      else
        puts "⚠️  Data issues found: #{response}"
        @cleaned_data = raw_data # In real app, you'd fix issues
      end
      puts
    }

    # Step 2: Perform analysis (with retry capability)
    prompt text: lambda {
      "Analyze this dataset and provide insights:\n\n#{cleaned_data}\n\n" \
        "Focus on trends, patterns, and key statistics."
    }, if: -> { !cleaned_data.nil? }, until: -> { analysis_results.any? || retry_count > 2 }, success: lambda { |response|
      if response.length > 50 # Simple validation
        @analysis_results[:insights] = response
        puts "✅ Analysis complete"
      else
        @retry_count += 1
        puts "⚠️  Analysis insufficient, retry #{retry_count}/3"
      end
      puts
    }

    # Step 3: Generate summary
    prompt text: lambda {
      "Based on this analysis:\n\n#{analysis_results[:insights]}\n\n" \
        "Create a concise executive summary (2-3 sentences)."
    }, if: -> { analysis_results[:insights] }, success: lambda { |response|
      @analysis_results[:summary] = response
      puts "✅ Summary generated"
      puts
    }

    def run!
      puts "📊 Data Processing Workflow"
      puts "=" * 60
      puts

      execute_prompt_chain

      puts "=" * 60
      puts "📈 Final Results"
      puts "=" * 60
      puts

      if analysis_results[:summary]
        puts "Summary:"
        puts analysis_results[:summary]
        puts
        puts "-" * 60
        puts
        puts "Full Analysis:"
        puts analysis_results[:insights]
      else
        puts "❌ Analysis failed after #{retry_count} attempts"
      end

      puts
      puts "✨ Processing complete!"
    end

    def self.run!(data = nil)
      data ||= <<~DATA
        Sales Data Q1 2024:
        January: $125,000 (target: $120,000)
        February: $118,000 (target: $120,000)
        March: $142,000 (target: $120,000)
        Total: $385,000 (target: $360,000)
      DATA

      new(data).run!
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "🎯 Raix Prompt Chain Workflow Demo"
  puts "Multi-step AI workflows with conditional execution"
  puts "=" * 60
  puts

  # Demo 1: Research & Writing Workflow
  puts "Demo 1: Research & Writing Workflow"
  puts "=" * 60
  Examples::PromptChainWorkflow.run!

  puts "\n\n#{"=" * 60}\n\n"

  # Demo 2: Data Processing Workflow
  puts "Demo 2: Data Processing Workflow"
  puts "=" * 60
  Examples::DataProcessingWorkflow.run!

  puts "\n#{"=" * 60}"
  puts "✨ All workflow demos complete!"
  puts "\n💡 PromptDeclarations Features Demonstrated:"
  puts "   • Sequential prompt execution"
  puts "   • Conditional prompts (if:)"
  puts "   • Success callbacks for handling responses"
  puts "   • Retry logic (until:)"
  puts "   • State management between steps"
end
