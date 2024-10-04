# Ruby AI eXtensions

## What's Raix

Raix (pronounced "ray" because the x is silent) is a library that gives you everything you need to add discrete large-language model (LLM) AI components to your Ruby applications. Raix consists of proven code that has been extracted from [Olympia](https://olympia.chat), the world's leading virtual AI team platform, and probably one of the biggest and most successful AI chat projects written completely in Ruby.

Understanding the how to use discrete AI components in otherwise normal code is key to productively leveraging Raix, and the subject of a book written by Raix's author Obie Fernandez, titled [Patterns of Application Development Using AI](https://leanpub.com/patterns-of-application-development-using-ai). You can easily support the ongoing development of this project by buying the book at Leanpub.

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

#### Transcript Format

The transcript accepts both abbreviated and standard OpenAI message hash formats. The abbreviated format, suitable for system, assistant, and user messages is simply a mapping of `role => content`, as show in the example above.

```ruby
transcript << { user: "What is the meaning of life?" }
```

As mentioned, Raix also understands standard OpenAI messages hashes. The previous example could be written as:

```ruby
transcript << { role: "user", content: "What is the meaning of life?" }
```

One of the advantages of OpenRouter and the reason that it is used by default by this library is that it handles mapping message formats from the OpenAI standard to whatever other model you're wanting to use (Anthropic, Cohere, etc.)

### Use of Tools/Functions

The second (optional) module that you can add to your Ruby classes after `ChatCompletion` is `FunctionDispatch`. It lets you declare and implement functions to be called at the AI's discretion as part of a chat completion "loop" in a declarative, Rails-like "DSL" fashion.

Most end-user facing AI components that include functions should be invoked using `chat_completion(loop: true)`, so that the results of each function call are added to the transcript and chat completion is triggered again. The looping will continue until the AI generates a plain text response.

```ruby
class WhatIsTheWeather
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  function :check_weather, "Check the weather for a location", location: { type: "string" } do |arguments|
    "The weather in #{arguments[:location]} is hot and sunny"
  end
end

RSpec.describe WhatIsTheWeather do
  subject { described_class.new }

  it "can call a function and loop to provide text response" do
    subject.transcript << { user: "What is the weather in Zipolite, Oaxaca?" }
    response = subject.chat_completion(openai: "gpt-4o", loop: true)
    expect(response).to include("hot and sunny")
  end
end
```

#### Manually Stopping a Loop

To loop AI components that don't interact with end users, at least one function block should invoke `stop_looping!` whenever you're ready to stop processing.

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
    # will continue looping until `stop_looping!` is called
    chat_completion(loop: true)
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
    stop_looping!
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

  # many other declarations ommitted...

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

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add raix

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install raix

If you are using the default OpenRouter API, Raix expects `Raix.configuration.openrouter_client` to initialized with the OpenRouter API client instance.

You can add an initializer to your application's `config/initializers` directory:

```ruby
  # config/initializers/raix.rb
  Raix.configure do |config|
    config.openrouter_client = OpenRouter::Client.new
  end
```

You will also need to configure the OpenRouter API access token as per the instructions here: https://github.com/OlympiaAI/open_router?tab=readme-ov-file#quickstart

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

Specs require `OR_ACCESS_TOKEN` and `OAI_ACCESS_TOKEN` environment variables, for access to OpenRouter and OpenAI, respectively. You can add those keys to a local unversionsed `.env` file and they will be picked up by the `dotenv` gem.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[OlympiaAI]/raix. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[OlympiaAI]/raix/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Raix project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[OlympiaAI]/raix/blob/main/CODE_OF_CONDUCT.md).
