## [Unreleased]

## [0.1.0] - 2024-04-03

- Initial release, placeholder gem

## [0.2.0] - tbd
- adds `ChatCompletion` module
- adds `PromptDeclarations` module
- adds `FunctionDispatch` module

## [0.3.2] - 2024-06-29
- adds support for streaming

## [0.4.0] - 2024-10-18
- adds support for Anthropic-style prompt caching
- defaults to `max_completion_tokens` when using OpenAI directly

## [0.4.2] - 2024-11-05
- adds support for [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs) with the `prediction` option for OpenAI

## [0.4.3] - 2024-11-11
- adds support for `Predicate` module

## [0.4.4] - 2024-11-11
- adds support for multiple tool calls in a single response

## [0.4.5] - 2024-11-11
- adds support for `ResponseFormat`
- added some missing requires to support String#squish
