# frozen_string_literal: true

require "ruby_llm"
require "zeitwerk"

# Ruby AI eXtensions
module Raix
  class << self
    attr_writer :configuration
  end

  # Returns the current configuration instance.
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Configures the Raix gem using a block.
  def self.configure
    yield(configuration)
  end
end

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("mcp" => "MCP")
loader.setup
