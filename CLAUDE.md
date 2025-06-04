This is a Ruby gem called Raix. Its purpose is to facilitate chat completion style AI text generation using LLMs provided by OpenAI and OpenRouter.

- When running all tests just do `bundle exec rake` since it automatically runs the linter with autocorrect
- Documentation: Include method/class documentation with examples when appropriate
- Add runtime dependencies to `raix.gemspec`.
- Add development dependencies to `Gemfile`.
- Don't ever test private methods directly. Specs should test behavior, not implementation.
- Never add test-specific code embedded in production code
- **Do not use require_relative**
- Require statements should always be in alphabetical order
- Always leave a blank line after module includes and before the rest of the class
- Do not decide unilaterally to leave code for the sake of "backwards compatibility"... always run those decisions by me first.
- Don't ever commit and push changes unless directly told to do so