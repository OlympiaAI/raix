# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MCP type coercion" do
  let(:test_class) do
    Class.new do
      include Raix::ChatCompletion
      include Raix::MCP

      def self.name
        "TestMcpTypeCoercion"
      end
    end
  end

  it "coerces string numbers to numeric types based on schema" do
    instance = test_class.new

    # Test integer coercion
    schema = {
      "properties" => {
        "x" => { "type" => "integer" },
        "y" => { "type" => "number" },
        "enabled" => { "type" => "boolean" },
        "items" => { "type" => "array" },
        "data" => { "type" => "object" }
      }
    }

    arguments = {
      "x" => "100",
      "y" => "50.5",
      "enabled" => "true",
      "items" => "[1, 2, 3]",
      "data" => '{"key": "value"}'
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    expect(result["x"]).to eq(100)
    expect(result["x"]).to be_a(Integer)

    expect(result["y"]).to eq(50.5)
    expect(result["y"]).to be_a(Float)

    expect(result["enabled"]).to eq(true)
    expect(result["enabled"]).to be_a(TrueClass)

    expect(result["items"]).to eq([1, 2, 3])
    expect(result["items"]).to be_a(Array)

    expect(result["data"]).to eq({ "key" => "value" })
    expect(result["data"]).to be_a(Hash)
  end

  it "preserves non-string values" do
    instance = test_class.new

    schema = {
      "properties" => {
        "x" => { "type" => "integer" },
        "y" => { "type" => "number" }
      }
    }

    arguments = { "x" => 100, "y" => 50.5 }
    result = instance.send(:coerce_arguments, arguments, schema)

    expect(result["x"]).to eq(100)
    expect(result["y"]).to eq(50.5)
  end

  it "coerces arrays of objects with item schemas" do
    instance = test_class.new

    schema = {
      "properties" => {
        "users" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "integer" },
              "age" => { "type" => "number" },
              "active" => { "type" => "boolean" }
            }
          }
        }
      }
    }

    arguments = {
      "users" => [
        { "id" => "123", "age" => "25.5", "active" => "true" },
        { "id" => "456", "age" => "30", "active" => "false" }
      ]
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    expect(result["users"]).to be_a(Array)
    expect(result["users"].length).to eq(2)

    first_user = result["users"][0]
    expect(first_user["id"]).to eq(123)
    expect(first_user["id"]).to be_a(Integer)
    expect(first_user["age"]).to eq(25.5)
    expect(first_user["age"]).to be_a(Float)
    expect(first_user["active"]).to eq(true)
    expect(first_user["active"]).to be_a(TrueClass)

    second_user = result["users"][1]
    expect(second_user["id"]).to eq(456)
    expect(second_user["active"]).to eq(false)
  end

  it "handles nested object coercion" do
    instance = test_class.new

    schema = {
      "properties" => {
        "config" => {
          "type" => "object",
          "properties" => {
            "settings" => {
              "type" => "object",
              "properties" => {
                "max_retries" => { "type" => "integer" },
                "timeout" => { "type" => "number" },
                "debug" => { "type" => "boolean" }
              }
            },
            "metadata" => {
              "type" => "object",
              "properties" => {
                "version" => { "type" => "number" }
              }
            }
          }
        }
      }
    }

    arguments = {
      "config" => {
        "settings" => {
          "max_retries" => "3",
          "timeout" => "30.5",
          "debug" => "true"
        },
        "metadata" => {
          "version" => "1.2"
        }
      }
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    expect(result["config"]["settings"]["max_retries"]).to eq(3)
    expect(result["config"]["settings"]["max_retries"]).to be_a(Integer)
    expect(result["config"]["settings"]["timeout"]).to eq(30.5)
    expect(result["config"]["settings"]["timeout"]).to be_a(Float)
    expect(result["config"]["settings"]["debug"]).to eq(true)
    expect(result["config"]["metadata"]["version"]).to eq(1.2)
  end

  it "handles JSON string inputs for arrays and objects" do
    instance = test_class.new

    schema = {
      "properties" => {
        "tags" => { "type" => "array" },
        "config" => {
          "type" => "object",
          "properties" => {
            "enabled" => { "type" => "boolean" }
          }
        }
      }
    }

    arguments = {
      "tags" => '["tag1", "tag2", "tag3"]',
      "config" => '{"enabled": "true", "extra": "value"}'
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    expect(result["tags"]).to eq(["tag1", "tag2", "tag3"])
    expect(result["config"]["enabled"]).to eq(true)
    expect(result["config"]["extra"]).to eq("value") # preserves extra properties
  end

  it "handles invalid JSON gracefully" do
    instance = test_class.new

    schema = {
      "properties" => {
        "data" => { "type" => "array" }
      }
    }

    arguments = {
      "data" => "not valid json ["
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    # Should return the original value when JSON parsing fails
    expect(result["data"]).to eq("not valid json [")
  end

  it "handles type mismatches gracefully" do
    instance = test_class.new

    schema = {
      "properties" => {
        "count" => { "type" => "integer" },
        "ratio" => { "type" => "number" },
        "flag" => { "type" => "boolean" }
      }
    }

    arguments = {
      "count" => "not a number",
      "ratio" => "also not a number",
      "flag" => "maybe"
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    # Should return original values when coercion is not possible
    expect(result["count"]).to eq("not a number")
    expect(result["ratio"]).to eq("also not a number")
    expect(result["flag"]).to eq("maybe")
  end

  it "preserves additional properties not in schema" do
    instance = test_class.new

    schema = {
      "properties" => {
        "known" => { "type" => "integer" }
      }
    }

    arguments = {
      "known" => "42",
      "unknown" => "value",
      "extra" => { "nested" => true }
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    expect(result["known"]).to eq(42)
    expect(result["unknown"]).to eq("value")
    expect(result["extra"]).to eq({ "nested" => true })
  end

  it "handles symbol and string keys interchangeably" do
    instance = test_class.new

    schema = {
      "properties" => {
        "value" => { "type" => "integer" }
      }
    }

    arguments = {
      value: "100"  # symbol key
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    expect(result["value"]).to eq(100)
    expect(result[:value]).to eq(100) # with_indifferent_access allows both
  end

  it "handles nil values appropriately" do
    instance = test_class.new

    schema = {
      "properties" => {
        "optional_int" => { "type" => "integer" },
        "optional_bool" => { "type" => "boolean" }
      }
    }

    arguments = {
      "optional_int" => nil,
      "other_field" => "value"
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    # nil values are preserved as-is (not coerced)
    expect(result["optional_int"]).to be_nil
    expect(result["other_field"]).to eq("value")
  end

  it "coerces boolean edge cases correctly" do
    instance = test_class.new

    schema = {
      "properties" => {
        "bool1" => { "type" => "boolean" },
        "bool2" => { "type" => "boolean" },
        "bool3" => { "type" => "boolean" },
        "bool4" => { "type" => "boolean" }
      }
    }

    arguments = {
      "bool1" => true,
      "bool2" => false,
      "bool3" => "true",
      "bool4" => "false"
    }

    result = instance.send(:coerce_arguments, arguments, schema)

    expect(result["bool1"]).to eq(true)
    expect(result["bool2"]).to eq(false)
    expect(result["bool3"]).to eq(true)
    expect(result["bool4"]).to eq(false)
  end
end
