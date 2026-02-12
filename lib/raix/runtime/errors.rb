# frozen_string_literal: true

module Raix
  module Runtime
    class Error < StandardError; end

    class ConfigurationError < Error; end

    # Wraps provider/transport errors with normalized metadata.
    class TransportError < Error
      attr_reader :status, :provider, :body

      def initialize(message, status: nil, provider: nil, body: nil)
        super(message)
        @status = status
        @provider = provider
        @body = body
      end
    end
  end
end
