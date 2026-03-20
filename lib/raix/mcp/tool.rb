module Raix
  module MCP
    # Represents an MCP (Model Context Protocol) tool with metadata and schema
    #
    # @example
    #   tool = Tool.new(
    #     name: "weather",
    #     description: "Get weather info",
    #     input_schema: { "type" => "object", "properties" => { "city" => { "type" => "string" } } }
    #   )
    class Tool
      attr_reader :name, :description, :input_schema

      # Initialize a new Tool
      #
      # @param name [String] the tool name
      # @param description [String] human-readable description of what the tool does
      # @param input_schema [Hash] JSON schema defining the tool's input parameters
      def initialize(name:, description:, input_schema: {})
        @name = name
        @description = description
        @input_schema = input_schema
      end

      # Initialize from raw MCP JSON response
      #
      # @param json [Hash] parsed JSON data from MCP response
      # @return [Tool] new Tool instance
      def self.from_json(json)
        new(
          name: json[:name] || json["name"],
          description: json[:description] || json["description"],
          input_schema: json[:inputSchema] || json["inputSchema"] || {}
        )
      end

      # Get the input schema type
      #
      # @return [String, nil] the schema type (e.g., "object")
      def input_type
        input_schema["type"]
      end

      # Get the properties hash
      #
      # @return [Hash] schema properties definition
      def properties
        input_schema["properties"] || {}
      end

      # Get required properties array
      #
      # @return [Array<String>] list of required property names
      def required_properties
        input_schema["required"] || []
      end

      # Check if a property is required
      #
      # @param property_name [String] name of the property to check
      # @return [Boolean] true if the property is required
      def required?(property_name)
        required_properties.include?(property_name)
      end
    end
  end
end
