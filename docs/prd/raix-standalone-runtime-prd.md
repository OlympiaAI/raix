# PRD: Raix Standalone Runtime (Decouple from RubyLLM)

Date: 2026-02-11  
Status: Draft for implementation planning  
Owner: Raix maintainer

## 1) Context

Raix currently depends on `ruby_llm (~> 1.9)` and uses it for:

- chat object lifecycle and execution (`RubyLLM.chat`, `Chat#ask/#complete`)
- message model and transcript bridging (`RubyLLM::Message`, `TranscriptAdapter`)
- tool model bridging (`RubyLLM::Tool`, `FunctionToolAdapter`)
- provider transport and request/response parsing (OpenAI/OpenRouter through RubyLLM)
- global API key configuration (`RubyLLM.config`)

At the same time, Raix already re-implements major chat orchestration behavior:

- `chat_completion` request parameter assembly
- tool-call security checks and function dispatch
- multi-turn continuation loop after tool calls
- JSON mode handling and parsing
- prompt caching transform behavior for Anthropic-style cache controls
- hook pipeline (`before_completion`) with mutable context

This overlap means Raix is coupled to RubyLLM while still carrying its own runtime semantics. The goal is to absorb required runtime functionality into Raix so the gem is standalone and controlled by Raix maintainers.

## 2) Problem Statement

Raix has product and roadmap risk from a hard runtime dependency on an external maintainer and architecture direction. This creates:

- roadmap blocking for Raix-specific features
- forced adaptation to upstream design choices
- reduced ability to guarantee behavior stability for Raix users
- duplicated logic across two chat runtimes

## 3) Goals

1. Remove hard dependency on `ruby_llm` for core Raix behavior.
2. Preserve public Raix behavior and API compatibility for existing users.
3. Keep provider support needed by Raix use-cases (OpenAI direct and OpenRouter routing).
4. Preserve module-level features: `ChatCompletion`, `FunctionDispatch`, `PromptDeclarations`, `Predicate`, `MCP`, `ResponseFormat`, `before_completion`.
5. Improve Raix autonomy for future features (including features currently blocked by RubyLLM gaps).

## 4) Non-Goals

1. Recreate all RubyLLM product surface (embeddings, moderation, images, transcription, ActiveRecord integrations, provider catalog and model registry tooling).
2. Build a full chat UI framework.
3. Introduce breaking API changes in this extraction phase unless explicitly versioned and documented.

## 5) Scope

### In Scope

- A new internal Raix runtime for chat completion and tool orchestration.
- Provider adapters for OpenAI and OpenRouter.
- Internal transport layer (Faraday-based), retries, streaming parsing, error mapping.
- Internal message and tool-call representations.
- Replacement/removal of `TranscriptAdapter` and `FunctionToolAdapter`.
- Configuration migration from RubyLLM-based keys to Raix-native keys.
- Backward compatibility shim for migration window.
- Updated tests, docs, examples, and changelog.

### Out of Scope (for initial standalone release)

- Native direct adapters for Anthropic, Gemini, Bedrock, etc. (can be added later via adapter pattern).
- Model discovery and remote model registry refresh features.
- Any broad DSL redesign.

## 6) Current Dependency Inventory

### Coupling points in current code

- `lib/raix.rb`: hard `require "ruby_llm"`.
- `lib/raix/chat_completion.rb`: `RubyLLM.chat`, `ruby_llm_request`, `ruby_llm_chat`.
- `lib/raix/transcript_adapter.rb`: depends on `RubyLLM::Chat#messages`.
- `lib/raix/function_tool_adapter.rb`: subclasses `RubyLLM::Tool`.
- `lib/raix/configuration.rb`: `ruby_llm_config`, checks `RubyLLM.config` keys.
- `raix.gemspec`: runtime dependency on `ruby_llm`.

### Practical behavior gap to address

- Raix currently routes non-OpenAI models to OpenRouter (`determine_provider`), so direct provider support promised by RubyLLM is not actually fully exploited by Raix.
- Predicted outputs support is partially blocked in tests due RubyLLM behavior.
- Two tool loop implementations overlap (`RubyLLM::Chat#complete` tool loop + Raix loop in `chat_completion`).

## 7) Target Product Definition

Raix ships with an internal, provider-agnostic chat runtime:

- `Raix::Runtime::ChatSession`
- `Raix::Runtime::Message`, `Raix::Runtime::ToolCall`, `Raix::Runtime::Chunk`
- `Raix::Runtime::Providers::{OpenAI, OpenRouter}`
- `Raix::Runtime::Transport` (HTTP, retries, streaming parser, errors)

`Raix::ChatCompletion` remains the public API surface and delegates to runtime internals.

## 8) Functional Requirements

### A. API Compatibility

FR-001: `ChatCompletion#chat_completion` must keep current signature and defaults (`params:`, `loop:`, `json:`, `raw:`, `openai:`, `save_response:`, `messages:`, `available_tools:`, `max_tool_calls:`).  
Acceptance: Existing specs using this signature continue to pass without call-site changes.

FR-002: `loop:` must remain accepted and emit deprecation warning, without changing behavior.  
Acceptance: Passing `loop: true` does not break request execution.

FR-003: `transcript` must continue to accept both abbreviated and standard message formats.  
Acceptance: Existing transcript usage patterns in README/examples/specs remain valid.

FR-004: `save_response` semantics must be preserved.  
Acceptance: Response is appended to transcript only when `save_response: true`.

FR-005: `messages:` override must bypass object transcript for that call while preserving existing race-safety behavior.  
Acceptance: Concurrent calls with explicit `messages:` do not corrupt transcript ordering.

FR-006: `raw: true` returns provider-normalized raw response object in current OpenAI-compatible envelope shape.  
Acceptance: Existing consumers expecting `choices[0].message` continue to work.

FR-007: Class-level `configure` and fallback behavior must remain available.  
Acceptance: Per-class config override of global config remains intact.

FR-008: `Configuration#client?` continues to report readiness, but against Raix-native config fields.  
Acceptance: Equivalent true/false outcomes for configured and unconfigured states.

FR-009: Public modules and constants remain available (`ChatCompletion`, `FunctionDispatch`, `PromptDeclarations`, `Predicate`, `MCP`, `ResponseFormat`, `CompletionContext`, `UndeclaredToolError`).  
Acceptance: Existing includes and references compile and behave.

### B. Chat Runtime and Message Handling

FR-010: Implement internal message model with roles `system|user|assistant|tool`, content, tool_calls, tool_call_id, usage metadata, and raw payload.  
Acceptance: All existing message transforms and transcript operations supported.

FR-011: Preserve content handling for both string and structured/multipart content arrays (needed for prompt caching and tool messages).  
Acceptance: Anthropic-style multipart payload paths continue to work.

FR-012: Normalize outputs to OpenAI-compatible shape used by current Raix logic.  
Acceptance: `response.dig("choices", 0, "message", "content")` continues to work.

FR-013: Preserve `Thread.current[:chat_completion_response]` assignment behavior.  
Acceptance: Prompt caching and existing debugging workflows can still access last raw response.

FR-014: Preserve `strip` behavior for non-raw string responses.  
Acceptance: Trailing whitespace is stripped while internal line breaks remain.

FR-015: Preserve empty transcript guard (`Can't complete an empty transcript`).  
Acceptance: Call fails fast for empty request context.

FR-016: Provide an internal transcript store that removes dependence on RubyLLM message objects.  
Acceptance: `TranscriptAdapter` no longer required for core operation.

### C. Provider and Transport

FR-017: Implement OpenAI provider adapter (chat completions sync + stream) with API key auth and optional org/project headers.  
Acceptance: Current OpenAI tests and examples pass.

FR-018: Implement OpenRouter provider adapter (chat completions sync + stream) with API key auth.  
Acceptance: Current OpenRouter-based tests and examples pass.

FR-019: Provider selection must preserve current behavior:
- explicit `openai:` selects OpenAI
- `gpt-*` and `o*` model IDs select OpenAI
- all other models select OpenRouter  
Acceptance: Selection matches existing `determine_provider` outcomes.

FR-020: Implement retry, timeout, and error mapping comparable to current behavior.  
Acceptance: network failures raise stable Raix runtime errors with useful provider messages.

FR-021: Streaming must support incremental callback tokens/chunks with existing `self.stream = lambda { |chunk| ... }` usage.  
Acceptance: streaming examples continue to work without API change.

FR-022: Streaming accumulator must reconstruct final content/tool calls for downstream logic.  
Acceptance: final response object in non-stream and stream modes is consistent.

FR-023: Pass-through params support for existing attr-backed generation controls:
`cache_at`, `frequency_penalty`, `logit_bias`, `logprobs`, `max_completion_tokens`, `max_tokens`, `min_p`, `prediction`, `presence_penalty`, `provider`, `repetition_penalty`, `response_format`, `seed`, `stop`, `temperature`, `tool_choice`, `top_a`, `top_k`, `top_logprobs`, `top_p`.  
Acceptance: parameters are included in payload where applicable and ignored safely otherwise.

FR-024: Preserve JSON parse retry behavior for blank/invalid JSON in JSON mode.  
Acceptance: retry path and error behavior remain compatible.

### D. Tools and Function Dispatch

FR-025: Preserve function declaration DSL and schema generation (`function :name, description, **params`).  
Acceptance: existing function declarations produce equivalent tool schemas.

FR-026: Preserve parameter flags `required` and `optional`.  
Acceptance: required arrays and properties remain as today.

FR-027: Preserve tool filtering via `available_tools`:
- `nil` => all declared tools
- `false` => no tools
- array => filtered tools, error on undeclared tools  
Acceptance: `UndeclaredToolError` behavior preserved.

FR-028: Preserve security check that only declared function names may be dispatched.  
Acceptance: unauthorized tool name raises and is never `public_send`-ed.

FR-029: Preserve automatic continuation loop after tool calls until text answer is produced.  
Acceptance: function-dispatch integration tests keep returning final assistant text.

FR-030: Preserve support for multiple tool calls in one assistant message.  
Acceptance: all tool calls in a single turn are executed before continuation.

FR-031: Preserve `max_tool_calls` and `stop_tool_calls_and_respond!` behavior.  
Acceptance: forced non-tool final response path remains functional.

### E. Hooks, Context, and Mutation

FR-032: Preserve `before_completion` at global, class, and instance levels.  
Acceptance: merge order global -> class -> instance remains unchanged.

FR-033: Preserve mutable `CompletionContext` contract (`messages`, `params`, helpers).  
Acceptance: message mutation use cases (redaction/injection/filtering) continue to work.

FR-034: Allow hooks to override model and arbitrary params.  
Acceptance: overridden model is used in provider call.

FR-035: Ignore non-callable hooks and non-hash hook return values safely.  
Acceptance: no exceptions from benign hook misuse.

FR-036: Preserve hook execution timing (post-transform, pre-request).  
Acceptance: hooks receive OpenAI-format request messages as now.

### F. Higher-Level Modules

FR-037: `PromptDeclarations` behavior remains compatible, including prompt ordering, conditions (`if`, `unless`, `until`), callbacks, stream handling, and `chat_completion_from_superclass`.  
Acceptance: prompt declaration specs continue to pass.

FR-038: `Predicate` behavior remains compatible (`yes?`, `no?`, `maybe?`, required handler validation).  
Acceptance: predicate specs continue to pass.

FR-039: `MCP` integration remains functionally unchanged (tool discovery, proxy calls, transcript logging, type coercion).  
Acceptance: MCP specs continue to pass without RubyLLM runtime dependency.

FR-040: `ResponseFormat` integration remains compatible with `chat_completion` JSON/structured output behavior.  
Acceptance: response format specs and examples remain valid.

FR-041: Preserve current public error classes where possible; new runtime errors must be namespaced and documented.  
Acceptance: common rescue paths remain stable or receive documented replacements.

### G. Migration and Packaging

FR-042: Remove runtime dependency on `ruby_llm` from gemspec.  
Acceptance: gem installs and runs without RubyLLM present.

FR-043: Remove `require "ruby_llm"` from Raix runtime files.  
Acceptance: require graph resolves cleanly.

FR-044: Update docs/examples to use Raix-native configuration.  
Acceptance: no required `RubyLLM.configure` in primary setup docs.

FR-045: Provide migration shim for one major version window:
- Read legacy config where practical
- Emit deprecation warnings for RubyLLM-specific config usage  
Acceptance: existing apps can migrate with guided warnings.

FR-046: Publish migration guide with old/new configuration mappings and behavioral notes.  
Acceptance: guide covers all breaking and non-breaking deltas.

## 9) Non-Functional Requirements

NFR-001 Reliability: error handling must classify provider/network failures and return actionable messages.

NFR-002 Availability: no new single point of failure compared to current architecture.

NFR-003 Performance: added Raix-side overhead for request orchestration should be minimal relative to provider latency.

NFR-004 Concurrency safety: transcript updates and tool call append operations must remain race-safe.

NFR-005 Backward compatibility: existing public API usage should continue to work for the targeted major release.

NFR-006 Security: no dynamic dispatch beyond declared functions; avoid leaking API keys in logs/exceptions.

NFR-007 Observability: request/response logging hooks remain feasible without monkey patches.

NFR-008 Testability: runtime components must be unit-testable in isolation (provider adapter, parser, tool loop, hook pipeline).

NFR-009 Maintainability: provider adapters follow shared interface with low coupling.

NFR-010 Extensibility: adding a new provider should not require edits to core chat orchestration.

NFR-011 Documentation quality: examples and README must accurately reflect runtime behavior and configuration.

NFR-012 Determinism: seed and core params pass-through behavior remains stable where providers support it.

NFR-013 Memory discipline: long transcript and streaming paths should avoid unnecessary object churn.

NFR-014 Compliance with semantic versioning: breaking changes are explicit and documented.

NFR-015 Governance autonomy: Raix release cadence and feature roadmap are not blocked by RubyLLM changes.

## 10) Architecture Decisions (High Level)

1. Create an internal provider abstraction (`ProviderAdapter`) with OpenAI and OpenRouter implementations first.
2. Keep Raix public API stable; replace internals incrementally behind existing modules.
3. Normalize provider outputs into a consistent OpenAI-like envelope used by current Raix flow.
4. Keep tool loop orchestration in Raix (single source of truth).
5. Avoid rebuilding non-chat RubyLLM domains (embeddings/moderation/images/transcription) in this phase.

## 11) Delivery Plan (Tasks and Dependencies)

No time estimates are included by design.

### Phase 0: Contract Freeze

T01: Build behavior contract from current specs and README examples.  
Depends on: none

T02: Freeze compatibility matrix (API, params, transcript, hooks, tool loop).  
Depends on: T01

### Phase 1: Runtime Foundation

T03: Introduce `Raix::Runtime::Config` and map current `Configuration` fields.  
Depends on: T02

T04: Implement internal runtime data models (`Message`, `ToolCall`, `Chunk`, `ResponseEnvelope`).  
Depends on: T02

T05: Implement transcript store replacement and remove RubyLLM message coupling.  
Depends on: T04

T06: Implement transport layer (Faraday connection setup, timeout, retry, error middleware).  
Depends on: T03

T07: Define provider adapter interface and registry.  
Depends on: T04, T06

### Phase 2: Provider Adapters

T08: Implement OpenAI adapter (sync request/response + streaming).  
Depends on: T07

T09: Implement OpenRouter adapter (sync request/response + streaming).  
Depends on: T07

T10: Implement streaming parser and accumulator shared by adapters.  
Depends on: T06

T11: Implement provider error normalization and response usage mapping.  
Depends on: T08, T09

### Phase 3: Chat Orchestration

T12: Replace `ruby_llm_request` with runtime request executor.  
Depends on: T05, T08, T09, T10, T11

T13: Port parameter mapping and defaults from existing `chat_completion`.  
Depends on: T12

T14: Port JSON mode, response_format behavior, and retry parsing logic.  
Depends on: T13

T15: Port prompt caching transforms (`cache_at` multipart handling).  
Depends on: T13

T16: Port stream callback behavior and final response handling.  
Depends on: T12, T10

### Phase 4: Tools and Hooks

T17: Replace `FunctionToolAdapter` with native tool schema serializer.  
Depends on: T04, T12

T18: Preserve available_tools filtering, undeclared-tool validation, and dispatch security checks.  
Depends on: T17

T19: Preserve multi-tool loop, max_tool_calls, and stop flag behavior.  
Depends on: T12, T18

T20: Preserve hook pipeline (`before_completion`) and `CompletionContext` mutation contract.  
Depends on: T13

### Phase 5: Module Compatibility

T21: Verify and adapt `PromptDeclarations` integration with new runtime.  
Depends on: T13, T20

T22: Verify and adapt `Predicate` integration with new runtime.  
Depends on: T13

T23: Validate `MCP` behavior remains unchanged under new runtime.  
Depends on: T19

T24: Keep `ResponseFormat` behavior and ensure integration tests pass.  
Depends on: T14

### Phase 6: Migration and Cleanup

T25: Remove `ruby_llm` requires and runtime references (`ruby_llm_chat`, adapters).  
Depends on: T12, T17

T26: Remove `ruby_llm` gem dependency from `raix.gemspec`; update Gemfile lock expectations.  
Depends on: T25

T27: Add migration shim/deprecation warnings for legacy configuration.  
Depends on: T03, T25

T28: Update README, examples, and upgrade notes to Raix-native setup.  
Depends on: T26, T27

T29: Update changelog and publish migration guide.  
Depends on: T28

### Phase 7: Verification and Release Readiness

T30: Add/refresh unit tests for runtime internals and provider adapters.  
Depends on: T08, T09, T10, T11, T12

T31: Run compatibility test matrix across existing specs and representative examples.  
Depends on: T21, T22, T23, T24, T30

T32: Add concurrency/regression tests for transcript and tool loop race-safety.  
Depends on: T19, T30

T33: Release candidate checklist and cut standalone-ready version.  
Depends on: T29, T31, T32

## 12) Critical Path

T01 -> T02 -> T03/T04/T06/T07 -> T08/T09/T10/T11 -> T12 -> T13 -> T17/T18/T19 -> T25/T26 -> T28 -> T31 -> T33

## 13) Risks and Mitigations

R1: Behavior drift in tool-loop orchestration.  
Mitigation: lock behavior with contract tests copied from current specs and VCR fixtures.

R2: Streaming regressions across providers.  
Mitigation: adapter-level streaming integration tests and accumulator unit tests.

R3: Configuration migration breakage for existing apps.  
Mitigation: migration shim + warnings + explicit upgrade guide.

R4: Hidden coupling in examples/docs/test helpers.  
Mitigation: CI checks for `require "ruby_llm"` in runtime/docs/examples after migration.

R5: Loss of future provider breadth previously implied by RubyLLM.  
Mitigation: keep adapter architecture and document supported providers clearly (OpenAI + OpenRouter initially).

## 14) Open Decisions

D1: Should Raix vNext include direct Anthropic/Gemini adapters or keep OpenRouter as primary route for non-OpenAI models?

D2: Should the migration shim for RubyLLM-style configuration exist for one minor or one major cycle?

D3: Should Raix introduce its own namespaced error taxonomy now, or mirror current errors for one release and migrate later?

## 15) Success Criteria

1. Raix installs and runs without RubyLLM dependency.
2. Existing public API and primary behavior remain compatible for targeted modules.
3. Specs for chat, tools, hooks, predicate, prompt declarations, and MCP pass against the new runtime.
4. Migration guide exists and covers all changed setup paths.
5. Raix can ship runtime changes without being blocked by RubyLLM maintainership or release cycle.
