# frozen_string_literal: true

module Raix
  module Runtime
    module Providers
      # Shared provider adapter base class.
      class Base
        attr_reader :configuration, :transport

        def initialize(configuration:, transport: nil)
          @configuration = configuration
          @transport = transport || Transport.new
        end
      end
    end
  end
end
