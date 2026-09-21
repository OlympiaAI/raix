# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::MultimodalContentAdapter do
  # 2x2 solid-red PNG
  let(:red_png_base64) do
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEUlEQVR4nGP8z8Dwn4EIwDiqEAAQOAQBjEZ1pgAAAABJRU5ErkJggg=="
  end
  let(:data_uri) { "data:image/png;base64,#{red_png_base64}" }

  describe ".translate" do
    it "decodes a data-URI image_url part into an image attachment" do
      content = [{ type: "image_url", image_url: { url: data_uri } }]

      result = described_class.translate(content)

      expect(result.attachments.size).to eq(1)
      attachment = RubyLLM::Attachment.wrap(result.attachments).first
      expect(attachment).to be_image
      expect(attachment.mime_type).to eq("image/png")
    end

    it "passes an http image_url part through as a URL attachment" do
      content = [{ type: "image_url", image_url: { url: "https://example.com/red.png" } }]

      result = described_class.translate(content)

      attachment = RubyLLM::Attachment.wrap(result.attachments).first
      expect(attachment).to be_url
      expect(attachment.source.to_s).to eq("https://example.com/red.png")
    end

    it "decodes any base64 data URI into a bare binary IO regardless of media type" do
      svg_uri = "data:image/svg+xml;base64,#{Base64.strict_encode64("<svg xmlns='http://www.w3.org/2000/svg'/>")}"
      content = [{ type: "image_url", image_url: { url: svg_uri } }]

      result = described_class.translate(content)

      source = result.attachments.first
      expect(source).to be_a(StringIO)
      expect(source.external_encoding).to eq(Encoding::BINARY)
      expect(source.read).to start_with("<svg")
    end

    it "treats the data: scheme case-insensitively, like the http(s) check" do
      content = [{ type: "image_url", image_url: { url: "DATA:image/png;BASE64,#{red_png_base64}" } }]

      result = described_class.translate(content)

      expect(result.attachments.size).to eq(1)
    end

    it "skips image_url values that are neither http(s) URLs nor data URIs" do
      content = [
        { type: "text", text: "look at this" },
        { type: "image_url", image_url: { url: "/etc/hostname" } },
        { type: "image_url", image_url: { url: "file:///etc/hostname" } },
        { type: "image_url", image_url: { url: "data:image/png,not-base64" } }
      ]

      result = described_class.translate(content)

      expect(result.attachments).to be_empty
      expect(result.content).to eq("look at this")
    end

    it "keeps the text part alongside the image attachment" do
      content = [
        { type: "text", text: "What color is this?" },
        { type: "image_url", image_url: { url: data_uri } }
      ]

      result = described_class.translate(content)

      expect(result.content).to eq("What color is this?")
      expect(result.attachments.size).to eq(1)
    end

    it "accepts string-keyed parts (OpenAI JSON shape)" do
      content = [{ "type" => "image_url", "image_url" => { "url" => data_uri } }]

      result = described_class.translate(content)

      expect(result.attachments.size).to eq(1)
    end

    it "returns plain string content unchanged" do
      result = described_class.translate("just text")

      expect(result.content).to eq("just text")
      expect(result.attachments).to be_empty
      expect(result).not_to be_cache_boundary
    end

    it "treats an empty content array as structured content with nothing in it" do
      result = described_class.translate([])

      expect(result.content).to be_nil
      expect(result.attachments).to be_empty
      expect(result).not_to be_cache_boundary
    end

    it "joins a text-only content array into a string" do
      content = [{ type: "text", text: "hello" }, { type: "text", text: "world" }]

      result = described_class.translate(content)

      expect(result.content).to eq("hello\nworld")
      expect(result.attachments).to be_empty
    end

    it "flags a part carrying cache_control as a cache boundary" do
      content = [
        { type: "text", text: "preamble" },
        { type: "text", text: "the long bit", cache_control: { type: "ephemeral" } }
      ]

      result = described_class.translate(content)

      expect(result).to be_cache_boundary
      expect(result.content).to eq("preamble\nthe long bit")
      expect(result.cache_ttl).to be_nil
    end

    it "surfaces a cache_control ttl so it can be forwarded to RubyLLM" do
      content = [{ type: "text", text: "stable", cache_control: { type: "ephemeral", ttl: "1h" } }]

      result = described_class.translate(content)

      expect(result.cache_ttl).to eq("1h")
    end
  end
end
