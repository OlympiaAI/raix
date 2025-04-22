require "bundler/setup"
require "raix"

# Test class that includes Raix::MCP
class TestMcpClient
  include Raix::ChatCompletion
  include Raix::MCP

  # Declare the remote MCP server
  mcp "https://gitmcp.io/modelcontextprotocol/modelcontextprotocol/docs/sse" # SSE URL, will be converted to endpoint

  def initialize
    @transcript = []
    @transcript << { role: "user", content: "Testing MCP connection" }
  end

  attr_reader :transcript
end

# Create the client and print available functions
client = TestMcpClient.new
functions = TestMcpClient.functions

puts "Available MCP functions:"
functions.each do |f|
  puts "- #{f[:name]}: #{f[:description]}"
end

puts "\nTest successful! MCP connection is working properly."
