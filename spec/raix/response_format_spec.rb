# frozen_string_literal: true

RSpec.describe Raix::ResponseFormat do
  RSpec::Matchers.define :serialize_to do |expected|
    match do |actual|
      @actual = JSON.pretty_generate(actual.to_schema)
      @expected = JSON.pretty_generate(expected)
      @actual_json == @expected_json
    end

    diffable
  end

  describe "complex nested structure with arrays" do
    it "matches the expected schema" do
      schema = {
        observations: [
          {
            brief: {
              type: "string",
              description: "brief description of the observation",
              required: true
            },
            content: {
              type: "string",
              description: "content of the observation",
              required: true
            },
            importance: {
              type: "integer",
              description: "importance of the observation",
              required: true
            }
          }
        ]
      }

      expect(described_class.new("observations", schema)).to serialize_to(
        {
          "type": "json_schema",
          "json_schema": {
            "name": "observations",
            "schema": {
              "type": "object",
              "properties": {
                "observations": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "brief": {
                        "type": "string",
                        "description": "brief description of the observation"
                      },
                      "content": {
                        "type": "string",
                        "description": "content of the observation"
                      },
                      "importance": {
                        "type": "integer",
                        "description": "importance of the observation"
                      }
                    },
                    "required": %w[brief content importance],
                    "additionalProperties": false
                  }
                }
              },
              "required": ["observations"],
              "additionalProperties": false
            },
            "strict": true
          }
        }
      )
    end
  end

  describe "simple schema with basic types" do
    it "matches the expected schema" do
      schema = {
        name: { type: "string" },
        age: { type: "integer" }
      }

      expect(described_class.new("PersonInfo", schema)).to serialize_to(
        {
          "type": "json_schema",
          "json_schema": {
            "name": "PersonInfo",
            "schema": {
              "type": "object",
              "properties": {
                "name": {
                  "type": "string"
                },
                "age": {
                  "type": "integer"
                }
              },
              "required": %w[name age],
              "additionalProperties": false
            },
            "strict": true
          }
        }
      )
    end
  end

  describe "nested structure with arrays" do
    it "matches the expected schema" do
      schema = {
        company: {
          name: { type: "string" },
          employees: [
            {
              name: { type: "string" },
              role: { type: "string" },
              skills: ["string"]
            }
          ],
          locations: ["string"]
        }
      }

      expect(described_class.new("CompanyInfo", schema)).to serialize_to(
        {
          "type": "json_schema",
          "json_schema": {
            "name": "CompanyInfo",
            "schema": {
              "type": "object",
              "properties": {
                "company": {
                  "name": {
                    "type": "string"
                  },
                  "employees": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "name": {
                          "type": "string"
                        },
                        "role": {
                          "type": "string"
                        },
                        "skills": {
                          "type": "array",
                          "items": {
                            "type": "string"
                          }
                        }
                      },
                      "required": [],
                      "additionalProperties": false
                    }
                  },
                  "locations": {
                    "type": "array",
                    "items": {
                      "type": "string"
                    }
                  }
                }
              },
              "required": ["company"],
              "additionalProperties": false
            },
            "strict": true
          }
        }
      )
    end
  end

  describe "person analysis example" do
    it "matches the expected schema" do
      schema = {
        full_name: { type: "string" },
        age_estimate: { type: "integer" },
        personality_traits: ["string"]
      }

      expect(described_class.new("PersonAnalysis", schema)).to serialize_to(
        {
          "type": "json_schema",
          "json_schema": {
            "name": "PersonAnalysis",
            "schema": {
              "type": "object",
              "properties": {
                "full_name": {
                  "type": "string"
                },
                "age_estimate": {
                  "type": "integer"
                },
                "personality_traits": {
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                }
              },
              "required": %w[full_name age_estimate personality_traits],
              "additionalProperties": false
            },
            "strict": true
          }
        }
      )
    end
  end
end
