# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::FunctionToolAdapter do
  let(:instance_class) do
    Class.new do
      include Raix::ChatCompletion
      include Raix::FunctionDispatch

      function :upsert_entity,
               "Create or update an entity.",
               type: { type: "string", description: "Class URI." },
               uri: { type: "string", description: "Entity URI." },
               properties: {
                 type: "object",
                 description: "Literal predicates keyed by prefixed name.",
                 additionalProperties: { type: "string" }
               },
               links: {
                 type: "object",
                 description: "URI predicates keyed by prefixed name.",
                 additionalProperties: { type: "string" }
               } do |args|
        args
      end

      function :ping, "no-args function" do |_args|
        :pong
      end
    end
  end

  describe ".create_tool_from_function" do
    it "forwards rich JSON-schema fields (additionalProperties, etc.) on object parameters" do
      tool = described_class.create_tool_from_function(instance_class.functions[0], instance_class.new)
      schema = tool.parameters_schema

      properties_param = schema["properties"]["properties"]
      expect(properties_param["type"]).to eq("object")
      expect(properties_param["additionalProperties"]).to eq("type" => "string")

      links_param = schema["properties"]["links"]
      expect(links_param["additionalProperties"]).to eq("type" => "string")
    end

    it "preserves strict OpenAI-style guards at the outer schema by default" do
      tool = described_class.create_tool_from_function(instance_class.functions[0], instance_class.new)
      schema = tool.parameters_schema

      expect(schema["additionalProperties"]).to eq(false)
      expect(schema["strict"]).to eq(true)
    end

    it "declares an empty object schema for functions with no parameters" do
      tool = described_class.create_tool_from_function(instance_class.functions[1], instance_class.new)

      expect(tool.parameters_schema).to eq(
        "type" => "object",
        "properties" => {},
        "required" => [],
        "additionalProperties" => false,
        "strict" => true
      )
    end
  end
end
