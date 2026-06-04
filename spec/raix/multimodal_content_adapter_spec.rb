# frozen_string_literal: true

require "spec_helper"

RSpec.describe Raix::MultimodalContentAdapter do
  # 2x2 solid-red PNG
  let(:red_png_base64) do
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEUlEQVR4nGP8z8Dwn4EIwDiqEAAQOAQBjEZ1pgAAAABJRU5ErkJggg=="
  end
  let(:data_uri) { "data:image/png;base64,#{red_png_base64}" }

  describe ".translate" do
    it "turns a data-URI image_url part into a RubyLLM::Content with a decoded image attachment" do
      content = [{ type: "image_url", image_url: { url: data_uri } }]

      result = described_class.translate(content)

      expect(result).to be_a(RubyLLM::Content)
      expect(result.attachments.size).to eq(1)
      attachment = result.attachments.first
      expect(attachment).to be_image
      expect(attachment.mime_type).to eq("image/png")
    end

    it "turns an http image_url part into a RubyLLM::Content with a URL attachment" do
      content = [{ type: "image_url", image_url: { url: "https://example.com/red.png" } }]

      result = described_class.translate(content)

      expect(result).to be_a(RubyLLM::Content)
      attachment = result.attachments.first
      expect(attachment).to be_url
      expect(attachment.source.to_s).to eq("https://example.com/red.png")
    end

    it "keeps the text part alongside the image attachment" do
      content = [
        { type: "text", text: "What color is this?" },
        { type: "image_url", image_url: { url: data_uri } }
      ]

      result = described_class.translate(content)

      expect(result.text).to eq("What color is this?")
      expect(result.attachments.size).to eq(1)
    end

    it "accepts string-keyed parts (OpenAI JSON shape)" do
      content = [{ "type" => "image_url", "image_url" => { "url" => data_uri } }]

      result = described_class.translate(content)

      expect(result.attachments.size).to eq(1)
    end

    it "returns plain string content unchanged" do
      expect(described_class.translate("just text")).to eq("just text")
    end

    it "leaves a text-only content array untouched" do
      content = [{ type: "text", text: "hello" }]

      expect(described_class.translate(content)).to equal(content)
    end
  end
end
