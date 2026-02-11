# Raix Examples

This directory contains working examples demonstrating various Raix features and modules.

## Setup

All examples require API keys to be configured. Create a `.env` file in the project root with:

```bash
OR_ACCESS_TOKEN=your_openrouter_api_key
OAI_ACCESS_TOKEN=your_openai_api_key
```

Make sure to run examples with `bundle exec`:

```bash
bundle exec ruby examples/example_name.rb
```

## Environment Variables

### Common Variables

- **`RAIX_DEBUG`** - Set to any value to enable detailed logging of LLM interactions (requests/responses)
- **`RAIX_EXAMPLE_MODEL`** - Override the default model for examples that support it

### Example Usage

```bash
# Run with debug logging enabled
RAIX_DEBUG=1 bundle exec ruby examples/live_chat_completion.rb

# Use a different model
RAIX_EXAMPLE_MODEL="gpt-4o" bundle exec ruby examples/live_chat_completion.rb

# Combine both
RAIX_DEBUG=1 RAIX_EXAMPLE_MODEL="gpt-4o" bundle exec ruby examples/live_chat_completion.rb
```

## Available Examples

### 1. Live Chat Completion

**File:** `live_chat_completion.rb`

**Demonstrates:**
- Basic chat completion with `ChatCompletion` module
- Function/tool definitions using `FunctionDispatch`
- Tool calls and automatic continuation until text response

**Features:**
- Defines a `current_time` function that returns UTC time
- Configurable via `RAIX_EXAMPLE_MODEL` and `RAIX_EXAMPLE_PROMPT`
- Shows how functions are automatically called when the AI requests them

**Usage:**

```bash
# Default prompt
bundle exec ruby examples/live_chat_completion.rb

# Custom prompt
RAIX_EXAMPLE_PROMPT="What time is it?" bundle exec ruby examples/live_chat_completion.rb

# With debug logging
RAIX_DEBUG=1 bundle exec ruby examples/live_chat_completion.rb

# Use OpenAI model
RAIX_EXAMPLE_MODEL="gpt-4o-mini" bundle exec ruby examples/live_chat_completion.rb
```

### 2. Code Reviewer

**File:** `code_reviewer.rb`

**Demonstrates:**
- The `Predicate` module for yes/no questions
- Handler blocks for yes/no/maybe responses
- Processing multiple questions in sequence
- Tracking results across multiple calls

**Features:**
- Reviews three different code snippets
- Provides approval/rejection with detailed explanations
- Shows summary statistics at the end
- Non-interactive demonstration

**Usage:**

```bash
# Run code review demo
bundle exec ruby examples/code_reviewer.rb

# With debug logging to see full AI interactions
RAIX_DEBUG=1 bundle exec ruby examples/code_reviewer.rb
```

**Example Output:**

```
🤖 AI Code Reviewer Demo
============================================================

Example 1: Clean Ruby code
🔍 Reviewing code...
------------------------------------------------------------
✅ APPROVED
   the code is following Ruby best practices...

============================================================
📊 Review Summary:
   ✅ Approved: 1
   ❌ Rejected: 2
   ⚠️  Unclear:  0
   📝 Total:    3
```

### 3. Trivia Game

**File:** `trivia_game.rb`

**Demonstrates:**
- The `Predicate` module in an interactive context
- User input handling
- Dynamic yes/no question evaluation
- Score tracking and result presentation

**Features:**
- Interactive command-line trivia game
- AI judges whether your answers are correct
- Tracks score and shows percentage
- Supports custom questions via command line

**Usage:**

```bash
# Play with default questions
bundle exec ruby examples/trivia_game.rb

# Provide your own questions
bundle exec ruby examples/trivia_game.rb \
  "Ruby was invented in Japan" \
  "Python was released before Ruby" \
  "Rails was created in 2004"

# With debug logging
RAIX_DEBUG=1 bundle exec ruby examples/trivia_game.rb
```

**Example Session:**

```
🎮 Welcome to AI Trivia Game!
==================================================

Question 1: Ruby was created by Yukihiro Matsumoto
Your answer (true/false): true

✓ CORRECT! The user answered 'true', which is correct...

🏆 Final Score: 4/5
📊 Percentage: 80%
😊 Great job! Keep it up!
```

### 4. Structured Data Extraction

**File:** `structured_data_extraction.rb`

**Demonstrates:**
- The `ResponseFormat` module for schema-validated JSON output
- Extracting structured data from unstructured text
- Defining complex nested schemas
- Multiple extraction scenarios (people, products, meetings)

**Features:**
- Enforces strict JSON schema compliance
- Perfect for data pipelines and form filling
- Shows person, product, and meeting note extraction
- Schema definition with types, arrays, and nested objects

**Usage:**

```bash
# Run all extraction examples
bundle exec ruby examples/structured_data_extraction.rb

# With debug logging
RAIX_DEBUG=1 bundle exec ruby examples/structured_data_extraction.rb
```

**Example Output:**

```
📄 Input Text:
John Smith is a 32-year-old senior software engineer...

✅ Extracted Data:
{
  "full_name": "John Smith",
  "age": 32,
  "email": "john.smith@example.com",
  "occupation": "senior software engineer",
  "skills": ["Ruby", "Python", "JavaScript"],
  "experience_years": 8
}
```

### 5. Streaming Chat

**File:** `streaming_chat.rb`

**Demonstrates:**
- Real-time token-by-token response streaming
- Progress indicators during generation
- Performance metrics (tokens/second, word count)
- Interactive chat mode

**Features:**
- Simple streaming with character-by-character output
- Streaming with "thinking" progress indicator
- Performance metrics tracking
- Optional interactive chat session

**Usage:**

```bash
# Run streaming demos
bundle exec ruby examples/streaming_chat.rb

# Interactive chat mode
bundle exec ruby examples/streaming_chat.rb --interactive

# With debug logging
RAIX_DEBUG=1 bundle exec ruby examples/streaming_chat.rb
```

**Use Cases:**
- Responsive chat interfaces
- Progress indicators for long responses
- Live transcription displays
- Real-time content generation

### 6. JSON Mode Demo

**File:** `json_mode_demo.rb`

**Demonstrates:**
- JSON mode for flexible structured output
- Comparison with ResponseFormat's strict schemas
- Various use cases (sentiment analysis, comparisons, quizzes, recipes)
- AI-determined JSON structure

**Features:**
- Valid JSON without strict schema enforcement
- AI chooses optimal structure for the task
- Works across different providers
- Simpler than ResponseFormat when flexibility is needed

**Usage:**

```bash
# Run all JSON mode examples
bundle exec ruby examples/json_mode_demo.rb

# With debug logging
RAIX_DEBUG=1 bundle exec ruby examples/json_mode_demo.rb
```

**Key Difference:**
- **JSON Mode**: Flexible structure, AI decides format
- **ResponseFormat**: Strict schema, enforced validation

### 7. Prompt Chain Workflow

**File:** `prompt_chain_workflow.rb`

**Demonstrates:**
- The `PromptDeclarations` module for multi-step workflows
- Conditional prompt execution with `if:` conditions
- Success callbacks for processing responses
- Retry logic with `until:` loops
- State management between prompts

**Features:**
- Two complete workflow examples (research/writing and data processing)
- Shows sequential prompt execution
- Demonstrates conditional logic and callbacks
- Includes retry/loop capabilities

**Usage:**

```bash
# Run workflow demos
bundle exec ruby examples/prompt_chain_workflow.rb

# Custom research topic
RESEARCH_TOPIC="Machine Learning Trends" bundle exec ruby examples/prompt_chain_workflow.rb

# With debug logging
RAIX_DEBUG=1 bundle exec ruby examples/prompt_chain_workflow.rb
```

**Use Cases:**
- Multi-step research tasks
- Complex data processing pipelines
- Conversational sequences
- Automated content generation

### 8. Prompt Caching Demo

**File:** `prompt_caching_demo.rb`

**Demonstrates:**
- Anthropic-style prompt caching for cost reduction
- Caching large context (documents, character cards, knowledge bases)
- Cache hit benefits (speed and cost)
- Multiple queries against cached context

**Features:**
- Employee handbook Q&A example
- Character roleplaying with cached personality
- Shows cache performance benefits
- Demonstrates cost savings (up to 98% reduction)

**Usage:**

```bash
# Run caching demos (requires Anthropic model)
RAIX_EXAMPLE_MODEL="anthropic/claude-3-5-sonnet" bundle exec ruby examples/prompt_caching_demo.rb

# With debug logging
RAIX_DEBUG=1 RAIX_EXAMPLE_MODEL="anthropic/claude-3-5-sonnet" bundle exec ruby examples/prompt_caching_demo.rb
```

**Cost Savings:**
- First request: Full context processed (~1200 tokens)
- Cached requests: Only new message processed (~10-20 tokens)
- ~98% reduction in input token costs

**Use Cases:**
- RAG (Retrieval-Augmented Generation) applications
- Document analysis with multiple queries
- AI chatbots with large knowledge bases
- Character-based AI roleplaying

### 9. Advanced Tool Control

**File:** `advanced_tool_control.rb`

**Demonstrates:**
- Multiple tool calls in a single AI response
- `max_tool_calls` parameter for limiting function execution
- `stop_tool_calls_and_respond!` for early termination
- Autonomous agent patterns with safeguards

**Features:**
- Multiple parallel tool calls
- Configurable call limits to prevent runaway loops
- Early termination from within functions
- Realistic order processing agent example

**Usage:**

```bash
# Run tool control demos
bundle exec ruby examples/advanced_tool_control.rb

# With debug logging
RAIX_DEBUG=1 bundle exec ruby examples/advanced_tool_control.rb
```

**Example Output:**

```
📋 Tool Call Log:
------------------------------------------------------------
1. search_database - 10:23:45.123
   Args: {:query=>"Q4 sales", :limit=>10}
2. calculate_stats - 10:23:45.456
   Args: {:dataset=>"sales", :metric=>"average"}
3. check_status - 10:23:45.789
   Args: {:system=>"analytics"}
```

**Use Cases:**
- Task automation with multiple steps
- Autonomous agents with safeguards
- Complex workflow orchestration
- Order processing with validations

### 10. Rails Initializer Example

**File:** `rails_initializer_example.rb`

**Demonstrates:**
- How to configure Raix in a Rails application
- Raix standalone runtime configuration options
- Logging setup with custom filtering
- Retry and timeout configuration

**Features:**
- Complete Rails initializer template
- Shows all available configuration options
- Includes custom logger example with sensitive data filtering
- Documents differences from previous Raix versions

**Usage:**

This file is a reference/template. Copy relevant sections to your Rails app's `config/initializers/raix.rb`.

## Module Overview

### ChatCompletion

The foundation module for LLM chat interactions.

**Key Features:**
- Transcript management
- Message formatting
- Automatic tool call handling
- Streaming support
- Multiple provider support (OpenAI, OpenRouter)

**Configuration:**
```ruby
class MyBot
  include Raix::ChatCompletion

  configure do |config|
    config.model = "gpt-4o"
    config.temperature = 0.7
    config.max_tokens = 1000
  end
end
```

### FunctionDispatch

DSL for declaring functions/tools that the AI can call.

**Key Features:**
- Clean function definition syntax
- Automatic JSON schema generation
- Type validation
- Integration with ChatCompletion

**Example:**
```ruby
class Assistant
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :get_weather,
    "Get weather for a location",
    location: { type: "string", required: true } do |args|
    # Implementation
    "Sunny, 72°F"
  end
end
```

### Predicate

Module for handling yes/no/maybe questions with custom handlers.

**Key Features:**
- Simple yes?/no?/maybe? block syntax
- Automatic response parsing
- Pattern matching on AI responses
- Clean separation of concerns

**Example:**
```ruby
class Decision
  include Raix::Predicate

  yes? { |explanation| puts "Approved: #{explanation}" }
  no? { |explanation| puts "Rejected: #{explanation}" }
  maybe? { |explanation| puts "Unclear: #{explanation}" }
end

decision = Decision.new
decision.ask("Is this code thread-safe?")
```

### ResponseFormat

Module for defining strict JSON schemas that the AI must follow in its response.

**Key Features:**
- Schema validation and enforcement
- Converts Ruby hash structures to OpenAI-compatible JSON schemas
- Perfect for structured data extraction
- Supports nested objects and arrays

**Example:**
```ruby
class DataExtractor
  include Raix::ChatCompletion

  def extract_person(text)
    format = Raix::ResponseFormat.new("Person", {
      name: { type: "string" },
      age: { type: "integer" },
      skills: ["string"]
    })

    transcript << { user: "Extract person info: #{text}" }
    chat_completion(params: { response_format: format })
  end
end
```

### PromptDeclarations

Module for building multi-step AI workflows with conditional execution and callbacks.

**Key Features:**
- Sequential prompt execution
- Conditional prompts with `if:` clauses
- Success callbacks for processing responses
- Retry logic with `until:` loops
- State management between steps

**Example:**
```ruby
class ResearchWorkflow
  include Raix::ChatCompletion
  include Raix::PromptDeclarations

  attr_accessor :research_data

  prompt text: -> { "Research topic: AI" }

  prompt text: -> { "Analyze findings" },
         if: -> { research_data },
         success: ->(response) { process_analysis(response) }

  prompt text: -> { "Generate report" },
         until: -> { report_complete? }
end
```

## Tips and Best Practices

1. **Always use `bundle exec`** to ensure you're using the local development version of Raix
2. **Enable debug logging** during development with `RAIX_DEBUG=1`
3. **Use environment variables** for API keys, never commit them
4. **Start with small examples** and build up to complex use cases
5. **Check token usage** in debug logs to optimize prompts
6. **Test with different models** to find the best balance of cost/quality

## Troubleshooting

### "Missing configuration for OpenRouter/OpenAI"

Make sure your `.env` file is in the project root and contains valid API keys:

```bash
OR_ACCESS_TOKEN=sk-or-v1-...
OAI_ACCESS_TOKEN=sk-...
```

### "No endpoints found for model"

The model might not be available on OpenRouter. Try using an OpenAI model instead:

```bash
RAIX_EXAMPLE_MODEL="gpt-4o-mini" bundle exec ruby examples/live_chat_completion.rb
```

### Examples not using local Raix code

Always use `bundle exec` to run examples. Without it, Ruby will load the installed gem instead of your local development code.

### Debug logging not showing

Make sure you're setting the environment variable before the command:

```bash
RAIX_DEBUG=1 bundle exec ruby examples/code_reviewer.rb
```

## Creating Your Own Examples

When creating new examples, follow this template:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv"
require "raix"

# Load environment variables
Dotenv.load

# Configure Raix
Raix.configure do |config|
  config.openrouter_api_key = ENV.fetch("OR_ACCESS_TOKEN", nil)
  config.openai_api_key = ENV.fetch("OAI_ACCESS_TOKEN", nil)
end

module Examples
  class YourExample
    include Raix::ChatCompletion

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.7
    end

    def run
      transcript << { user: "Your prompt here" }
      chat_completion
    end

    def self.run!
      new.run
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Examples::YourExample.run!
end
```

## Additional Resources

- [Raix Documentation](../README.md)
- [OpenRouter Models](https://openrouter.ai/models)
- [OpenAI Models](https://platform.openai.com/docs/models)
