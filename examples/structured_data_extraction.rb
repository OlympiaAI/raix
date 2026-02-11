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
  # Demonstrates the ResponseFormat feature for extracting structured data
  # from unstructured text using a strict JSON schema.
  class StructuredDataExtraction
    include Raix::ChatCompletion

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.1 # Low temperature for consistent extraction
    end

    # Extract person information from text
    def extract_person(text)
      puts "📄 Input Text:"
      puts text
      puts "\n" + "=" * 60

      # Define the schema for person data
      format = Raix::ResponseFormat.new("Person", {
        full_name: { type: "string" },
        age: { type: "integer" },
        email: { type: "string" },
        occupation: { type: "string" },
        skills: ["string"],
        experience_years: { type: "integer" }
      })

      transcript << {
        system: "You are a data extraction assistant. Extract information accurately from the provided text."
      }
      transcript << {
        user: "Extract the person's information from this text:\n\n#{text}"
      }

      puts "🔍 Extracting structured data...\n\n"
      result = chat_completion(params: { response_format: format })

      puts "✅ Extracted Data:"
      puts JSON.pretty_generate(result)
      puts

      result
    end

    # Extract product information from a description
    def extract_product(description)
      puts "📦 Product Description:"
      puts description
      puts "\n" + "=" * 60

      # Define schema for product data
      format = Raix::ResponseFormat.new("Product", {
        name: { type: "string" },
        category: { type: "string" },
        price: { type: "number" },
        currency: { type: "string" },
        features: ["string"],
        specifications: {
          type: "object",
          properties: {
            dimensions: { type: "string" },
            weight: { type: "string" },
            color: { type: "string" }
          }
        },
        in_stock: { type: "boolean" }
      })

      transcript << {
        system: "Extract product information from descriptions. If information is missing, use null."
      }
      transcript << {
        user: "Extract product details:\n\n#{description}"
      }

      puts "🔍 Extracting product data...\n\n"
      result = chat_completion(params: { response_format: format })

      puts "✅ Extracted Product:"
      puts JSON.pretty_generate(result)
      puts

      result
    end

    # Extract meeting notes into structured format
    def extract_meeting_notes(notes)
      puts "📝 Meeting Notes:"
      puts notes
      puts "\n" + "=" * 60

      format = Raix::ResponseFormat.new("MeetingNotes", {
        date: { type: "string" },
        attendees: ["string"],
        topics_discussed: ["string"],
        action_items: [
          {
            type: "object",
            properties: {
              task: { type: "string" },
              assignee: { type: "string" },
              due_date: { type: "string" }
            }
          }
        ],
        decisions_made: ["string"],
        next_meeting: { type: "string" }
      })

      transcript << {
        system: "Extract structured information from meeting notes. Be thorough and accurate."
      }
      transcript << {
        user: "Structure these meeting notes:\n\n#{notes}"
      }

      puts "🔍 Structuring meeting notes...\n\n"
      result = chat_completion(params: { response_format: format })

      puts "✅ Structured Notes:"
      puts JSON.pretty_generate(result)
      puts

      result
    end

    def self.run!
      extractor = new

      puts "🎯 Raix Structured Data Extraction Demo"
      puts "Using ResponseFormat for schema-validated JSON output"
      puts "=" * 60
      puts

      # Example 1: Person data extraction
      puts "Example 1: Extract Person Information"
      puts "-" * 60
      person_text = <<~TEXT
        John Smith is a 32-year-old senior software engineer at TechCorp.
        He has 8 years of experience and specializes in Ruby, Python, and JavaScript.
        His email is john.smith@example.com and he's passionate about AI and automation.
      TEXT
      extractor.extract_person(person_text)

      puts "\n" + "=" * 60 + "\n\n"

      # Example 2: Product data extraction
      puts "Example 2: Extract Product Information"
      puts "-" * 60
      product_text = <<~TEXT
        The UltraBook Pro 15 is a premium laptop in the Electronics category.
        Priced at $1,299 USD, it features a stunning 15.6" display, 16GB RAM,
        and 512GB SSD storage. The sleek aluminum chassis comes in Space Gray,
        weighs just 3.5 lbs, and measures 14 x 9.7 x 0.6 inches. Currently in stock
        with free shipping.
      TEXT
      extractor.extract_product(product_text)

      puts "\n" + "=" * 60 + "\n\n"

      # Example 3: Meeting notes extraction
      puts "Example 3: Extract Meeting Notes"
      puts "-" * 60
      meeting_text = <<~TEXT
        Team meeting on December 15, 2023. Present: Alice, Bob, and Carol.

        We discussed the Q4 roadmap and decided to prioritize the API refactoring project.
        Alice will update the documentation by December 20th.
        Bob agreed to review the security audit findings and present recommendations
        at our next meeting on December 22nd.
        Carol will coordinate with the design team for the new dashboard mockups,
        due before year-end.

        We also covered the budget allocation for next quarter and decided to
        increase the infrastructure budget by 15%.
      TEXT
      extractor.extract_meeting_notes(meeting_text)

      puts "\n" + "=" * 60
      puts "✨ All extractions complete!"
      puts "\nNote: ResponseFormat ensures the AI returns data matching your exact schema."
      puts "This is perfect for data pipelines, form filling, and structured analysis."
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Examples::StructuredDataExtraction.run!
end
