# Ruby AI eXtensions

## What's Raix

Raix (pronounced "ray" because the x is silent) is a library that gives you everything you need to add discrete large-language model (LLM) AI components to your Ruby applications. Raix consists of proven code that has been extracted from [Olympia](https://olympia.chat), the world's leading virtual AI team platform, and probably one of the biggest and most successful AI chat projects written completely in Ruby.

Understanding how to use discrete AI components in otherwise normal code is key to productively leveraging Raix, and the subject of a book written by Raix's author Obie Fernandez, titled [Patterns of Application Development Using AI](https://leanpub.com/patterns-of-application-development-using-ai). You can easily support the ongoing development of this project by buying the book at Leanpub.

At the moment, Raix natively supports use of either OpenAI or OpenRouter as its underlying AI provider. Eventually you will be able to specify your AI provider via an adapter, kind of like ActiveRecord maps to databases. Note that you can also use Raix to add AI capabilities to non-Rails applications as long as you include ActiveSupport as a dependency. Extracting the base code to its own standalone library without Rails dependencies is on the roadmap, but not a high priority.

### Chat Completions

Raix consists of three modules that can be mixed in to Ruby classes to give them AI powers. The first (and mandatory) module is `ChatCompletion`, which provides `transcript` and `chat_completion` methods.

```ruby
class MeaningOfLife
  include Raix::ChatCompletion
end

>> ai = MeaningOfLife.new
>> ai.transcript << { user: "What is the meaning of life?" }
>> ai.chat_completion

=> "The question of the meaning of life is one of the most profound and enduring inquiries in philosophy, religion, and science.
    Different perspectives offer various answers..."
```

By default, Raix will automatically add the AI's response to the transcript. This behavior can be controlled with the `save_response` parameter, which defaults to `true`. You may want to set it to `false` when making multiple chat completion calls during the lifecycle of a single object (whether sequentially or in parallel) and want to manage the transcript updates yourself:

```ruby
>> ai.chat_completion(save_response: false)
```

#### Transcript Format

The transcript accepts both abbreviated and standard OpenAI message hash formats. The abbreviated format, suitable for system, assistant, and user messages is simply a mapping of `role => content`, as shown in the example above.

```ruby
transcript << { user: "What is the meaning of life?" }
```

As mentioned, Raix also understands standard OpenAI messages hashes. The previous example could be written as:

```ruby
transcript << { role: "user", content: "What is the meaning of life?" }
```

One of the advantages of OpenRouter and the reason that it is used by default by this library is that it handles mapping message formats from the OpenAI standard to whatever other model you're wanting to use (Anthropic, Cohere, etc.)

Note that it's possible to override the current object's transcript by passing a `messages` array to `chat_completion`. This allows for multiple threads to share a single conversation context in parallel, by deferring when they write their responses back to the transcript.

```
chat_completion(openai: "gpt-4.1-nano", messages: [{ user: "What is the meaning of life?" }])
```

### Predicted Outputs

Raix supports [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs) with the `prediction` parameter for OpenAI.

```ruby
>> ai.chat_completion(openai: "gpt-4o", params: { prediction: })
```

### Prompt Caching

Raix supports [Anthropic-style prompt caching](https://openrouter.ai/docs/prompt-caching#anthropic-claude) when using Anthropic's Claude family of models. You can specify a `cache_at` parameter when doing a chat completion. If the character count for the content of a particular message is longer than the cache_at parameter, it will be sent to Anthropic as a multipart message with a cache control "breakpoint" set to "ephemeral".

Note that there is a limit of four breakpoints, and the cache will expire within five minutes. Therefore, it is recommended to reserve the cache breakpoints for large bodies of text, such as character cards, CSV data, RAG data, book chapters, etc. Raix does not enforce a limit on the number of breakpoints, which means that you might get an error if you try to cache too many messages.

```ruby
>> my_class.chat_completion(params: { cache_at: 1000 })
=> {
  "messages": [
    {
      "role": "system",
      "content": [
        {
          "type": "text",
          "text": "HUGE TEXT BODY LONGER THAN 1000 CHARACTERS",
          "cache_control": {
            "type": "ephemeral"
          }
        }
      ]
    },
```

### JSON Mode

Raix supports JSON mode for chat completions, which ensures that the AI model's response is valid JSON. This is particularly useful when you need structured data from the model.

When using JSON mode with OpenAI models, Raix will automatically set the `response_format` parameter on requests accordingly, and attempt to parse the entire response body as JSON.
When using JSON mode with other models (e.g. Anthropic) that don't support `response_format`, Raix will look for JSON content inside of &lt;json&gt; XML tags in the response, before
falling back to parsing the entire response body. Make sure you tell the AI to reply with JSON inside of XML tags.

```ruby
>> my_class.chat_completion(json: true)
=> { "key": "value" }
```

When using JSON mode with non-OpenAI providers, Raix automatically sets the `require_parameters` flag to ensure proper JSON formatting. You can also combine JSON mode with other parameters:

```ruby
>> my_class.chat_completion(json: true, openai: "gpt-4o")
=> { "key": "value" }
```

### Use of Tools/Functions

The second (optional) module that you can add to your Ruby classes after `ChatCompletion` is `FunctionDispatch`. It lets you declare and implement functions to be called at the AI's discretion in a declarative, Rails-like "DSL" fashion.

When the AI responds with tool function calls instead of a text message, Raix automatically:
1. Executes the requested tool functions
2. Adds the function results to the conversation transcript
3. Sends the updated transcript back to the AI for another completion
4. Repeats this process until the AI responds with a regular text message

This automatic continuation ensures that tool calls are seamlessly integrated into the conversation flow. The AI can use tool results to formulate its final response to the user. You can limit the number of tool calls using the `max_tool_calls` parameter to prevent excessive function invocations.

```ruby
class WhatIsTheWeather
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :check_weather,
           "Check the weather for a location",
           location: { type: "string", required: true } do |arguments|
    "The weather in #{arguments[:location]} is hot and sunny"
  end
end

RSpec.describe WhatIsTheWeather do
  subject { described_class.new }

  it "provides a text response after automatically calling weather function" do
    subject.transcript << { user: "What is the weather in Zipolite, Oaxaca?" }
    response = subject.chat_completion(openai: "gpt-4o")
    expect(response).to include("hot and sunny")
  end
end
```

Parameters are optional by default. Mark them as required with `required: true` or explicitly optional with `optional: true`.

Note that for security reasons, dispatching functions only works with functions implemented using `Raix::FunctionDispatch#function` or directly on the class.

#### Tool Filtering

You can control which tool functions are exposed to the AI per request using the `available_tools` parameter of the `chat_completion` method:

```ruby
class WeatherAndTime
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :check_weather, "Check the weather for a location", location: { type: "string" } do |arguments|
    "The weather in #{arguments[:location]} is sunny"
  end

  function :get_time, "Get the current time" do |_arguments|
    "The time is 12:00 PM"
  end
end

weather = WeatherAndTime.new

# Don't pass any tools to the LLM
weather.chat_completion(available_tools: false)

# Only pass specific tools to the LLM
weather.chat_completion(available_tools: [:check_weather])

# Pass all declared tools (default behavior)
weather.chat_completion
```

The `available_tools` parameter accepts three types of values:
- `nil`: All declared tool functions are passed (default behavior)
- `false`: No tools are passed to the LLM
- An array of symbols: Only the specified tools are passed (raises `Raix::UndeclaredToolError` if a specified tool function is not declared)

#### Multiple Tool Calls

Some AI models (like GPT-4) can make multiple tool calls in a single response. When this happens, Raix will automatically handle all the function calls sequentially.
If you need to capture the arguments to the function calls, do so in the block passed to `function`. The response from `chat_completion` is always the final text
response from the assistant, and is not affected by function calls.

```ruby
class MultipleToolExample
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  attr_reader :invocations

  function :first_tool do |arguments|
    @invocations << :first
    "Result from first tool"
  end

  function :second_tool do |arguments|
    @invocations << :second
    "Result from second tool"
  end

  def initialize
    @invocations = []
  end
end

example = MultipleToolExample.new
example.transcript << { user: "Please use both tools" }
example.chat_completion(openai: "gpt-4o")
# => "I used both tools, as requested"

example.invocations
# => [:first, :second]
```

#### Customizing Function Dispatch

You can customize how function calls are handled by overriding the `dispatch_tool_function` in your class. This is useful if you need to add logging, caching, error handling, or other custom behavior around function calls.

```ruby
class CustomDispatchExample
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :example_tool do |arguments|
    "Result from example tool"
  end

  def dispatch_tool_function(function_name, arguments)
    puts "Calling #{function_name} with #{arguments}"
    result = super
    puts "Result: #{result}"
    result
  end
end
```

#### Function Call Caching

You can use ActiveSupport's Cache to cache function call results, which can be particularly useful for expensive operations or external API calls that don't need to be repeated frequently.

```ruby
class CachedFunctionExample
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :expensive_operation do |arguments|
    "Result of expensive operation with #{arguments}"
  end

  # Override dispatch_tool_function to enable caching for all functions
  def dispatch_tool_function(function_name, arguments)
    # Pass the cache to the superclass implementation
    super(function_name, arguments, cache: Rails.cache)
  end
end
```

The caching mechanism works by:
1. Passing the cache object through `dispatch_tool_function` to the function implementation
2. Using the function name and arguments as cache keys
3. Automatically fetching from cache when available or executing the function when not cached

This is particularly useful for:
- Expensive database operations
- External API calls
- Resource-intensive computations
- Functions with deterministic outputs for the same inputs

#### Limiting Tool Calls

You can control the maximum number of tool calls before the AI must provide a text response:

```ruby
# Limit to 5 tool calls (default is 25)
response = my_ai.chat_completion(max_tool_calls: 5)

# Configure globally
Raix.configure do |config|
  config.max_tool_calls = 10
end
```

#### Manually Stopping Tool Calls

For AI components that process tasks without end-user interaction, you can use `stop_tool_calls_and_respond!` within a function to force the AI to provide a text response without making additional tool calls.

```ruby
class OrderProcessor
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  SYSTEM_DIRECTIVE = "You are an order processor, tasked with order validation, inventory check,
                      payment processing, and shipping."

  attr_accessor :order

  def initialize(order)
    self.order = order
    transcript << { system: SYSTEM_DIRECTIVE }
    transcript << { user: order.to_json }
  end

  def perform
    # will automatically continue after tool calls until finished_processing is called
    chat_completion
  end


  # implementation of functions that can be called by the AI
  # entirely at its discretion, depending on the needs of the order.
  # The return value of each `perform` method will be added to the
  # transcript of the conversation as a function result.

  function :validate_order do
    OrderValidationWorker.perform(@order)
  end

  function :check_inventory do
    InventoryCheckWorker.perform(@order)
  end

  function :process_payment do
    PaymentProcessingWorker.perform(@order)
  end

  function :schedule_shipping do
    ShippingSchedulerWorker.perform(@order)
  end

  function :send_confirmation do
    OrderConfirmationWorker.perform(@order)
  end

  function :finished_processing do
    order.update!(transcript:, processed_at: Time.current)
    stop_tool_calls_and_respond!
    "Order processing completed successfully"
  end
end
```

### Prompt Declarations

The third (also optional) module that you can add mix in along with `ChatCompletion` is `PromptDeclarations`. It provides the ability to declare a "Prompt Chain" (series of prompts to be called in a sequence), and also features a declarative, Rails-like "DSL" of its own. Prompts can be defined inline or delegate to callable prompt objects, which themselves implement `ChatCompletion`.

The following example is a rough excerpt of the main "Conversation Loop" in Olympia, which pre-processes user messages to check for
the presence of URLs and scan memory before submitting as a prompt to GPT-4. Note that prompt declarations are executed in the order
that they are declared. The `FetchUrlCheck` callable prompt class is included for instructional purposes. Note that it is passed the
an instance of the object that is calling it in its initializer as its `context`. The passing of context means that you can assemble
composite prompt structures of arbitrary depth.

```ruby
class PromptSubscriber
  include Raix::ChatCompletion
  include Raix::PromptDeclarations

  attr_accessor :conversation, :bot_message, :user_message

  # many other declarations omitted...

  prompt call: FetchUrlCheck

  prompt call: MemoryScan

  prompt text: -> { user_message.content }, stream: -> { ReplyStream.new(self) }, until: -> { bot_message.complete? }

  def initialize(conversation)
    self.conversation = conversation
  end

  def message_created(user_message)
    self.user_message = user_message
    self.bot_message = conversation.bot_message!(responding_to: user_message)

    chat_completion(loop: true, openai: "gpt-4o")
  end

  ...
end

class FetchUrlCheck
  include ChatCompletion
  include FunctionDispatch

  REGEX = %r{\b(?:http(s)?://)?(?:www\.)?[a-zA-Z0-9-]+(\.[a-zA-Z]{2,})+(/[^\s]*)?\b}

  attr_accessor :context, :conversation

  delegate :user_message, to: :context
  delegate :content, to: :user_message

  def initialize(context)
    self.context = context
    self.conversation = context.conversation
    self.model = "anthropic/claude-3-haiku"
  end

  def call
    return unless content&.match?(REGEX)

    transcript << { system: "Call the `fetch` function if the user mentions a website, otherwise say nil" }
    transcript << { user: content }

    chat_completion # TODO: consider looping to fetch more than one URL per user message
  end

  function :fetch, "Gets the plain text contents of a web page", url: { type: "string" } do |arguments|
    Tools::FetchUrl.fetch(arguments[:url]).tap do |result|
      parent = conversation.function_call!("fetch_url", arguments, parent: user_message)
      conversation.function_result!("fetch_url", result, parent:)
    end
  end

```

Notably, Olympia does not use the `FunctionDispatch` module in its primary conversation loop because it does not have a fixed set of tools that are included in every single prompt. Functions are made available dynamically based on a number of factors including the user's plan tier and capabilities of the assistant with whom the user is conversing.

Streaming of the AI's response to the end user is handled by the `ReplyStream` class, passed to the final prompt declaration as its `stream` parameter. [Patterns of Application Development Using AI](https://leanpub.com/patterns-of-application-development-using-ai) devotes a whole chapter to describing how to write your own `ReplyStream` class.

#### Additional PromptDeclarations Options

The `PromptDeclarations` module supports several additional options that can be used to customize prompt behavior:

```ruby
class CustomPromptExample
  include Raix::ChatCompletion
  include Raix::PromptDeclarations

  # Basic prompt with text
  prompt text: "Process this input"

  # Prompt with system directive
  prompt system: "You are a helpful assistant",
        text: "Analyze this text"

  # Prompt with conditions
  prompt text: "Process this input",
        if: -> { some_condition },
        unless: -> { some_other_condition }

  # Prompt with success callback
  prompt text: "Process this input",
        success: ->(response) { handle_response(response) }

  # Prompt with custom parameters
  prompt text: "Process with custom settings",
        params: { temperature: 0.7, max_tokens: 1000 }

  # Prompt with until condition for looping
  prompt text: "Keep processing until complete",
        until: -> { processing_complete? }

  # Prompt with raw response
  prompt text: "Get raw response",
        raw: true

  # Prompt using OpenAI directly
  prompt text: "Use OpenAI",
        openai: "gpt-4o"
end
```

The available options include:

- `system`: Set a system directive for the prompt
- `if`/`unless`: Control prompt execution with conditions
- `success`: Handle prompt responses with callbacks
- `params`: Customize API parameters per prompt
- `until`: Control prompt looping
- `raw`: Get raw API responses
- `openai`: Use OpenAI directly
- `stream`: Control response streaming
- `call`: Delegate to callable prompt objects

You can also access the current prompt context and previous responses:

```ruby
class ContextAwarePrompt
  include Raix::ChatCompletion
  include Raix::PromptDeclarations

  def process_with_context
    # Access current prompt
    current_prompt.params[:temperature]

    # Access previous response
    last_response

    chat_completion
  end
end
```

## Predicate Module

The `Raix::Predicate` module provides a simple way to handle yes/no/maybe questions using AI chat completion. It allows you to define blocks that handle different types of responses with their explanations. It is one of the concrete patterns described in the "Discrete Components" chapter of [Patterns of Application Development Using AI](https://leanpub.com/patterns-of-application-development-using-ai).

### Usage

Include the `Raix::Predicate` module in your class and define handlers using block syntax:

```ruby
class Question
  include Raix::Predicate

  yes? do |explanation|
    puts "Affirmative: #{explanation}"
  end

  no? do |explanation|
    puts "Negative: #{explanation}"
  end

  maybe? do |explanation|
    puts "Uncertain: #{explanation}"
  end
end

question = Question.new
question.ask("Is Ruby a programming language?")
# => Affirmative: Yes, Ruby is a dynamic, object-oriented programming language...
```

### Features

- Define handlers for yes, no, and/or maybe responses using the declarative class level block syntax.
- At least one handler (yes, no, or maybe) must be defined.
- Handlers receive the full AI response including explanation as an argument.
- Responses always start with "Yes, ", "No, ", or "Maybe, " followed by an explanation.
- Make sure to ask a question that can be answered with yes, no, or maybe (otherwise the results are indeterminate).

### Example with Single Handler

You can define only the handlers you need:

```ruby
class SimpleQuestion
  include Raix::Predicate

  # Only handle positive responses
  yes? do |explanation|
    puts "✅ #{explanation}"
  end
end

question = SimpleQuestion.new
question.ask("Is 2 + 2 = 4?")
# => ✅ Yes, 2 + 2 equals 4, this is a fundamental mathematical fact.
```

### Error Handling

The module will raise a RuntimeError if you attempt to ask a question without defining any response handlers:

```ruby
class InvalidQuestion
  include Raix::Predicate
end

question = InvalidQuestion.new
question.ask("Any question")
# => RuntimeError: Please define a yes and/or no block
```

## Model Context Protocol (Experimental)

The `Raix::MCP` module provides integration with the Model Context Protocol, allowing you to connect your Raix-powered application to remote MCP servers. This feature is currently **experimental**.

### Usage

Include the `Raix::MCP` module in your class and declare MCP servers using the `mcp` DSL:

```ruby
class McpConsumer
  include Raix::ChatCompletion
  include Raix::FunctionDispatch
  include Raix::MCP

  mcp "https://your-mcp-server.example.com/sse"
end
```

### Features

- Automatically fetches available tools from the remote MCP server using `tools/list`
- Registers remote tools as OpenAI-compatible function schemas
- Defines proxy methods that forward requests to the remote server via `tools/call`
- Seamlessly integrates with the existing `FunctionDispatch` workflow
- Handles transcript recording to maintain consistent conversation history

### Filtering Tools

You can filter which remote tools to include:

```ruby
class FilteredMcpConsumer
  include Raix::ChatCompletion
  include Raix::FunctionDispatch
  include Raix::MCP

  # Only include specific tools
  mcp "https://server.example.com/sse", only: [:tool_one, :tool_two]

  # Or exclude specific tools
  mcp "https://server.example.com/sse", except: [:tool_to_exclude]
end
```

## Response Format (Experimental)

The `ResponseFormat` class provides a way to declare a JSON schema for the response format of an AI chat completion. It's particularly useful when you need structured responses from AI models, ensuring the output conforms to your application's requirements.

### Features

- Converts Ruby hashes and arrays into JSON schema format
- Supports nested structures and arrays
- Enforces strict validation with `additionalProperties: false`
- Automatically marks all top-level properties as required
- Handles both simple type definitions and complex nested schemas

### Basic Usage

```ruby
# Simple schema with basic types
format = Raix::ResponseFormat.new("PersonInfo", {
  name: { type: "string" },
  age: { type: "integer" }
})

# Use in chat completion
my_ai.chat_completion(response_format: format)
```

### Complex Structures

```ruby
# Nested structure with arrays
format = Raix::ResponseFormat.new("CompanyInfo", {
  company: {
    name: { type: "string" },
    employees: [
      {
        name: { type: "string" },
        role: { type: "string" },
        skills: ["string"]
      }
    ],
    locations: ["string"]
  }
})
```

### Generated Schema

The ResponseFormat class generates a schema that follows this structure:

```json
{
  "type": "json_schema",
  "json_schema": {
    "name": "SchemaName",
    "schema": {
      "type": "object",
      "properties": {
        "property1": { "type": "string" },
        "property2": { "type": "integer" }
      },
      "required": ["property1", "property2"],
      "additionalProperties": false
    },
    "strict": true
  }
}
```

### Using with Chat Completion

When used with chat completion, the AI model will format its response according to your schema:

```ruby
class StructuredResponse
  include Raix::ChatCompletion

  def analyze_person(name)
    format = Raix::ResponseFormat.new("PersonAnalysis", {
      full_name: { type: "string" },
      age_estimate: { type: "integer" },
      personality_traits: ["string"]
    })

    transcript << { user: "Analyze the person named #{name}" }
    chat_completion(params: { response_format: format })
  end
end

response = StructuredResponse.new.analyze_person("Alice")
# Returns a hash matching the defined schema
```

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add raix

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install raix

If you are using the default OpenRouter API, Raix expects `Raix.configuration.openrouter_client` to initialized with the OpenRouter API client instance.

You can add an initializer to your application's `config/initializers` directory that looks like this example (setting up both providers, OpenRouter and OpenAI):

```ruby
  # config/initializers/raix.rb
  OpenRouter.configure do |config|
    config.faraday do |f|
      f.request :retry, retry_options
      f.response :logger, Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
        logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
      end
    end
  end

  Raix.configure do |config|
    config.openrouter_client = OpenRouter::Client.new(access_token: ENV.fetch("OR_ACCESS_TOKEN", nil))
    config.openai_client = OpenAI::Client.new(access_token: ENV.fetch("OAI_ACCESS_TOKEN", nil)) do |f|
      f.request :retry, retry_options
      f.response :logger, Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
        logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
      end
    end
  end
```

You will also need to configure the OpenRouter API access token as per the instructions here: https://github.com/OlympiaAI/open_router?tab=readme-ov-file#quickstart

### Custom Providers

You may register custom providers instead of either of the above by registering an object that responds
to `request(params:, model:, messages:)` and returns a OpenAI compatible chat completion response.

See the [OpenAIProvider implementation](/OlympiaAI/raix/blob/main/lib/raix/providers/openai_provider.rb) for the OpenAI compatible provider implementation.

### Global vs class level configuration

You can either configure Raix globally or at the class level. The global configuration is set in the initializer as shown above. You can however also override all configuration options of the `Configuration` class on the class level with the
same syntax:

```ruby
class MyClass
  include Raix::ChatCompletion

  configure do |config|
    config.openrouter_client = OpenRouter::Client.new # with my special options
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

Specs require `OR_ACCESS_TOKEN` and `OAI_ACCESS_TOKEN` environment variables, for access to OpenRouter and OpenAI, respectively. You can add those keys to a local unversioned `.env` file and they will be picked up by the `dotenv` gem.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/OlympiaAI/raix. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/OlympiaAI/raix/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Raix project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/OlympiaAI/raix/blob/main/CODE_OF_CONDUCT.md).
