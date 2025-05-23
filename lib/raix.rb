# frozen_string_literal: true

require_relative "raix/version"
require_relative "raix/configuration"
require_relative "raix/chat_completion"
require_relative "raix/function_dispatch"
require_relative "raix/prompt_declarations"
require_relative "raix/predicate"
require_relative "raix/response_format"
require_relative "raix/mcp"

# The Raix module provides configuration options for the Raix gem.
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
