# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::Runtime::StreamParser do
  subject(:parser) { described_class.new }

  it "extracts data events separated by LF" do
    chunk = "data: {\"a\":1}\n\ndata: {\"b\":2}\n\n"
    expect(parser.feed(chunk)).to eq(['{"a":1}', '{"b":2}'])
  end

  it "extracts data events separated by CRLF" do
    chunk = "data: {\"a\":1}\r\n\r\ndata: {\"b\":2}\r\n\r\n"
    expect(parser.feed(chunk)).to eq(['{"a":1}', '{"b":2}'])
  end

  it "buffers incomplete events until full delimiter arrives" do
    expect(parser.feed("data: {\"a\":1}\n")).to eq([])
    expect(parser.feed("\n")).to eq(['{"a":1}'])
  end

  it "ignores non-data lines" do
    chunk = ":comment\nevent: message\ndata: hello\n\n"
    expect(parser.feed(chunk)).to eq(["hello"])
  end
end
