# frozen_string_literal: true

RSpec.describe Raix::ResponseFormat do
  let(:input) do
    {
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
  end

  let(:rf) { described_class.new("observations", input) }

  xit "matches the expected schema" do
    json = JSON.pretty_generate({
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
                                })

    expect(rf.to_json.squish).to eq(json.squish)
  end
end
