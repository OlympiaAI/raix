# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::Runtime::Transport do
  subject(:transport) { described_class.new }

  let(:connection) { instance_double(Faraday::Connection) }

  before do
    allow(transport).to receive(:connection).and_return(connection)
  end

  describe "#post_json" do
    it "parses a successful JSON response" do
      response = instance_double(Faraday::Response, status: 200, body: '{"choices":[{"message":{"content":"ok"}}]}')
      allow(connection).to receive(:post).and_return(response)

      result = transport.post_json(url: "https://example.com", headers: {}, payload: {}, provider: "test")
      expect(result.dig("choices", 0, "message", "content")).to eq("ok")
    end

    it "raises a transport error for provider error responses" do
      response = instance_double(Faraday::Response, status: 400, body: '{"error":{"message":"bad request"}}')
      allow(connection).to receive(:post).and_return(response)

      expect do
        transport.post_json(url: "https://example.com", headers: {}, payload: {}, provider: "test")
      end.to raise_error(Raix::Runtime::TransportError, /bad request/)
    end

    it "raises a transport error for non-json responses" do
      response = instance_double(Faraday::Response, status: 502, body: "upstream failure")
      allow(connection).to receive(:post).and_return(response)

      expect do
        transport.post_json(url: "https://example.com", headers: {}, payload: {}, provider: "test")
      end.to raise_error(Raix::Runtime::TransportError, /non-JSON/)
    end
  end

  describe "#post_stream" do
    it "parses stream events and returns an assembled envelope" do
      allow(connection).to receive(:post) do |_url, &block|
        request = Struct.new(:options, :headers, :body).new(Faraday::RequestOptions.new, {}, nil)
        block.call(request)

        request.options.on_data.call("data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"},\"finish_reason\":null}]}\n\n", 0, nil)
        request.options.on_data.call("data: {\"choices\":[{\"delta\":{\"content\":\"lo\"},\"finish_reason\":\"stop\"}]}\n\n", 0, nil)
        request.options.on_data.call("data: [DONE]\n\n", 0, nil)
      end

      emitted = +""
      result = transport.post_stream(url: "https://example.com", headers: {}, payload: {}, provider: "test") { |chunk| emitted << chunk }

      expect(emitted).to eq("Hello")
      expect(result.dig("choices", 0, "message", "content")).to eq("Hello")
      expect(result.dig("choices", 0, "finish_reason")).to eq("stop")
    end
  end
end
