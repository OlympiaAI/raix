## [1.0.0] - 2025-06-04
### Breaking Changes
- **Deprecated `loop` parameter in ChatCompletion** - The system now automatically continues conversations after tool calls until the AI provides a text response. The `loop` parameter shows a deprecation warning but still works for backwards compatibility.
- **Tool-based completions now return strings instead of arrays** - When functions are called, the final response is a string containing the AI's text response, not an array of function results.
- **`stop_looping!` renamed to `stop_tool_calls_and_respond!`** - Better reflects the new automatic continuation behavior.

### Added
- **Automatic conversation continuation** - Chat completions automatically continue after tool execution without needing the `loop` parameter.
- **`max_tool_calls` parameter** - Controls the maximum number of tool invocations to prevent infinite loops (default: 25).
- **Configuration for `max_tool_calls`** - Added `max_tool_calls` to the Configuration class with sensible defaults.

### Changed
- ChatCompletion handles continuation after tool function calls automatically.
- Improved CI/CD workflow to use `bundle exec rake ci` for consistent testing.

### Fixed
- Resolved conflict between `loop` attribute and Ruby's `Kernel.loop` method (fixes #11).
- Fixed various RuboCop warnings using keyword argument forwarding.
- Improved error handling with proper warning messages instead of puts.

## [0.9.2] - 2025-06-03
### Fixed
- Fixed OpenAI chat completion compatibility
- Fixed SHA256 hexdigest generation for MCP tool names
- Added ostruct as explicit dependency to prevent warnings
- Fixed rubocop lint error for alphabetized gemspec dependencies
- Updated default OpenRouter model

## [0.9.1] - 2025-05-30
### Added
- **MCP Type Coercion** - Automatic type conversion for MCP tool arguments based on JSON schema
  - Supports integer, number, boolean, array, and object types
  - Handles nested objects and arrays of objects with proper coercion
  - Gracefully handles invalid JSON and type mismatches
- **MCP Image Support** - MCP tools can now return image content as structured JSON

### Fixed
- Fixed handling of nil values in MCP argument coercion

## [0.9.0] - 2025-05-30
### Added
- **MCP (Model Context Protocol) Support**
  - New `stdio_mcp` method for stdio-based MCP servers
  - Refactored existing MCP code into `SseClient` and `StdioClient`
  - Split top-level `mcp` method into `sse_mcp` and `stdio_mcp`
  - Added authentication support for MCP servers
- **Class-Level Configuration**
  - Moved configuration to separate `Configuration` class
  - Added fallback mechanism for configuration options
  - Cleaner metaprogramming implementation

### Fixed
- Fixed method signature of functions added via MCP

## [0.8.6] - 2025-05-19
- add `required` and `optional` flags for parameters in `function` declarations

## [0.8.5] - 2025-05-08
- renamed `tools` argument to `chat_completion` to `available_tools` to prevent shadowing the existing tool attribute (potentially breaking change to enhancement introduced in 0.8.1)

## [0.8.4] - 2025-05-07
- Calls strip instead of squish on response of chat_completion in order to not clobber linebreaks

## [0.8.3] - 2025-04-30
- Adds optional ActiveSupport Cache parameter to `dispatch_tool_function` for caching tool calls

## [0.8.2] - 2025-04-29
- Extracts function call dispatch into a public `dispatch_tool_function` that can be overridden in subclasses
- Uses `public_send` instead of `send` for better security and explicitness

## [0.8.1] - 2025-04-24
Added ability to filter tool functions (or disable completely) when calling `chat_completion`. Thanks to @parruda for the contribution.

## [0.8.0] - 2025-04-23
### Added
* **MCP integration (Experimental)** — new `Raix::MCP` concern and `mcp` DSL for declaring remote MCP servers.
  * Automatically fetches `tools/list`, registers remote tools as OpenAI‑compatible function schemas, and defines proxy methods that forward `tools/call`.
  * `ChatCompletion#tools` now returns remote MCP tools alongside local `function` declarations.

### Changed
* `lib/raix.rb` now requires `raix/mcp` so the concern is auto‑loaded.

### Fixed
* Internal transcript handling spec expectations updated.

### Specs
* Added `spec/raix/mcp_spec.rb` with comprehensive stubs for tools discovery & call flow.

## [0.7.3] - 2025-04-23
- commit function call and result to transcript in one operation for thread safety

## [0.7.2] - 2025-04-19
- adds support for `messages` parameter in `chat_completion` to override the transcript
- fixes potential race conditions in parallel chat completion calls by duplicating transcript

## [0.7.1] - 2025-04-10
- adds support for JSON response format with automatic parsing
- improves error handling for JSON parsing failures

## [0.7] - 2025-04-02
- adds support for `until` condition in `PromptDeclarations` to control prompt looping
- adds support for `if` and `unless` conditions in `PromptDeclarations` to control prompt execution
- adds support for `success` callback in `PromptDeclarations` to handle prompt responses
- adds support for `stream` handler in `PromptDeclarations` to control response streaming
- adds support for `params` in `PromptDeclarations` to customize API parameters per prompt
- adds support for `system` directive in `PromptDeclarations` to set per-prompt system messages
- adds support for `call` in `PromptDeclarations` to delegate to callable prompt objects
- adds support for `text` in `PromptDeclarations` to specify prompt content via lambda, string, or symbol
- adds support for `raw` parameter in `PromptDeclarations` to return raw API responses
- adds support for `openai` parameter in `PromptDeclarations` to use OpenAI directly
- adds support for `prompt` parameter in `PromptDeclarations` to specify initial prompt
- adds support for `last_response` in `PromptDeclarations` to access previous prompt responses
- adds support for `current_prompt` in `PromptDeclarations` to access current prompt context
- adds support for `MAX_LOOP_COUNT` in `PromptDeclarations` to prevent infinite loops
- adds support for `execute_ai_request` in `PromptDeclarations` to handle API calls
- adds support for `chat_completion_from_superclass` in `PromptDeclarations` to handle superclass calls
- adds support for `model`, `temperature`, and `max_tokens` in `PromptDeclarations` to access prompt parameters
- Make automatic JSON parsing available to non-OpenAI providers that don't support the response_format parameter by scanning for json XML tags

## [0.6.0] - 2024-11-12
- adds `save_response` option to `chat_completion` to control transcript updates
- fixes potential race conditions in transcript handling

## [0.4.8] - 2024-11-12
- adds documentation for `Predicate` maybe handler
- logs to stdout when a response is unhandled by `Predicate`

## [0.4.7] - 2024-11-12
- adds missing requires `raix/predicate` so that it can be used in a Rails app automatically
- adds missing openai support for `Predicate`

## [0.4.5] - 2024-11-11
- adds support for `ResponseFormat`
- added some missing requires to support String#squish

## [0.4.4] - 2024-11-11
- adds support for multiple tool calls in a single response

## [0.4.3] - 2024-11-11
- adds support for `Predicate` module

## [0.4.2] - 2024-11-05
- adds support for [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs) with the `prediction` option for OpenAI

## [0.4.0] - 2024-10-18
- adds support for Anthropic-style prompt caching
- defaults to `max_completion_tokens` when using OpenAI directly

## [0.3.2] - 2024-06-29
- adds support for streaming

## [0.2.0] - tbd
- adds `ChatCompletion` module
- adds `PromptDeclarations` module
- adds `FunctionDispatch` module

## [0.1.0] - 2024-04-03
- Initial release, placeholder gem
