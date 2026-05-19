# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "shellwords"
require "tmpdir"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new(:rubocop_ci)

task ci: %i[spec rubocop_ci]

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--autocorrect"]
end

task default: %i[spec rubocop]

namespace :release do
  desc "Create a GitHub release for the current version (runs automatically after `rake release`)"
  task :github do
    version = Bundler::GemHelper.gemspec.version.to_s
    tag = "v#{version}"
    section = File.read("CHANGELOG.md").match(/^## \[#{Regexp.escape(version)}\][^\n]*\n(.*?)(?=^## \[|\z)/m)

    if section.nil?
      warn "release:github — no CHANGELOG entry for #{version}; skipping GitHub release."
      next
    end

    notes_file = File.join(Dir.tmpdir, "raix-release-notes-#{version}.md")
    File.write(notes_file, "#{section[1].strip}\n")

    sh "gh release create #{tag.shellescape} --title #{"Release #{version}".shellescape} --notes-file #{notes_file.shellescape} --latest=true"
  end
end

Rake::Task["release"].enhance do
  Rake::Task["release:github"].invoke
end
