# frozen_string_literal: true

require_relative "lib/raix/version"

Gem::Specification.new do |spec|
  spec.name = "raix"
  spec.version = Raix::VERSION
  spec.authors = ["Obie Fernandez"]
  spec.email = ["obiefernandez@gmail.com"]

  spec.summary = "Ruby AI eXtensions"
  spec.homepage = "https://github.com/OlympiaAI/raix"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/OlympiaAI/raix"
  spec.metadata["changelog_uri"] = "https://github.com/OlympiaAI/raix/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 6.0"
  spec.add_dependency "open_router", "~> 0.2"
  spec.add_dependency "ruby-openai", "~> 7.0"
end
