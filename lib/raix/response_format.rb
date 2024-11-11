# frozen_string_literal: true

require "active_support/core_ext/object/deep_dup"
require "active_support/core_ext/string/filters"

module Raix
  # Handles the formatting of responses for AI interactions.
  #
  # This class is responsible for converting input data into a JSON schema
  # that can be used to structure and validate AI responses. It supports
  # nested structures and arrays, ensuring that the output conforms to
  # the expected format for AI model interactions.
  #
  # @example
  #   input = { name: { type: "string" }, age: { type: "integer" } }
  #   format = ResponseFormat.new("PersonInfo", input)
  #   schema = format.to_schema
  #
  # @attr_reader [String] name The name of the response format
  # @attr_reader [Hash] input The input data to be formatted
  class ResponseFormat
    def initialize(name, input)
      @name = name
      @input = input
    end

    def to_json(*)
      JSON.pretty_generate(to_schema)
    end

    def to_schema
      {
        type: "json_schema",
        json_schema: {
          name: @name,
          schema: {
            type: "object",
            properties: decode(@input.deep_dup),
            required: @input.keys,
            additionalProperties: false
          },
          strict: true
        }
      }
    end

    private

    def decode(input)
      {}.tap do |response|
        case input
        when Array
          properties = {}
          input.each { |item| properties.merge!(decode(item)) }

          response[:type] = "array"
          response[:items] = {
            type: "object",
            properties:,
            required: properties.keys.select { |key| properties[key].delete(:required) },
            additionalProperties: false
          }
        when Hash
          input.each do |key, value|
            response[key] = if value.is_a?(Hash) && value.key?(:type)
                              value
                            else
                              decode(value)
                            end
          end
        else
          raise "Invalid input"
        end
      end
    end
  end
end
