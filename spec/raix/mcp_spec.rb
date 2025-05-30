describe "type coercion" do
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
end
