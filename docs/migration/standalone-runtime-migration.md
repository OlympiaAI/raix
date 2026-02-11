# Raix Standalone Runtime Migration Guide

This guide covers migration from RubyLLM-backed Raix 2.0 to the standalone runtime.

## What Changed

- Raix no longer depends on `ruby_llm` at runtime.
- `Raix::ChatCompletion` now uses native OpenAI/OpenRouter provider adapters.
- `Raix.configure` is now the primary API-key configuration surface.

## New Configuration

```ruby
Raix.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
  config.openai_organization_id = ENV["OPENAI_ORG_ID"] # optional
  config.openai_project_id = ENV["OPENAI_PROJECT_ID"]  # optional
end
```

## Legacy Compatibility (Temporary)

Raix still reads legacy settings for one major-version migration window:

- `config.openai_client` / `config.openrouter_client` (deprecated)
- `config.ruby_llm_config` (deprecated shim)

When legacy settings are used, Raix emits deprecation warnings.

## Provider Selection Rules

Provider selection is unchanged:

- explicit `openai: "gpt-4o"` forces OpenAI
- models starting with `gpt-` or `o` use OpenAI
- all other models use OpenRouter

## Behavior Compatibility

The following behavior is preserved:

- `chat_completion` signature and defaults
- transcript acceptance of abbreviated and standard message formats
- tool declaration/filtering/dispatch security checks
- automatic tool-call continuation loop
- `max_tool_calls` and `stop_tool_calls_and_respond!`
- `before_completion` hook order (global -> class -> instance)
- `Thread.current[:chat_completion_response]` assignment

## Suggested Upgrade Steps

1. Remove `ruby_llm` initialization from app boot code.
2. Move API keys into `Raix.configure`.
3. Run your test suite and watch for deprecation warnings.
4. Remove deprecated legacy client or RubyLLM config usage.
