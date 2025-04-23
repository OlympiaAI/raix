## [0.7.3] - 2025-04-23

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
