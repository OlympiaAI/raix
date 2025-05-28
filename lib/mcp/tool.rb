module Raix
  module MCP
    class Tool
      attr_reader :name, :description, :input_schema

      def initialize(name:, description:, input_schema: {})
        @name = name
        @description = description
        @input_schema = input_schema
      end

      # Initialize from raw MCP JSON response
      def self.from_json(json)
        new(
          name: json["name"],
          description: json["description"],
          input_schema: json["inputSchema"] || {}
        )
      end

      # Get the input schema type
      def input_type
        input_schema["type"]
      end

      # Get the properties hash
      def properties
        input_schema["properties"] || {}
      end

      # Get required properties array
      def required_properties
        input_schema["required"] || []
      end

      # Check if a property is required
      def required?(property_name)
        required_properties.include?(property_name)
      end
    end
  end
end
