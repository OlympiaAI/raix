# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in raix-rails.gemspec
gemspec

gem "activesupport", ">= 6.0"
gem "faraday-retry"
gem "open_router", "~> 0.3"
gem "ruby-openai", "~> 7.0"

group :development do
  gem "dotenv", ">= 2"
  gem "guard"
  gem "guard-rspec"
  gem "pry", ">= 0.14"
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.0"
  gem "rubocop", "~> 1.21"
  gem "solargraph-rails", "~> 0.2.0.pre"
  gem "sorbet"
  gem "tapioca", require: false
end

group :test do
  gem "vcr"
  gem "webmock"
end
