# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"
require "base64"
require "stringio"

module Raix
  # Translates OpenAI-style multimodal content arrays (a `text` part plus one or
  # more `image_url` parts) into a RubyLLM::Content so images survive the trip to
  # the provider.
  #
  # RubyLLM's `add_message`/`ask` treat a raw array of OpenAI content hashes as
  # plain text, so an `{ type: "image_url", image_url: { url: ... } }` part is
  # silently dropped and a vision model receives text only. See
  # https://github.com/OlympiaAI/raix/issues/51
  #
  # Anything that is not an array of hashes containing at least one `image_url`
  # part is returned untouched, so existing text completions are unaffected.
  class MultimodalContentAdapter
    def self.translate(content)
      new(content).translate
    end

    def initialize(content)
      @content = content
    end

    def translate
      return @content unless translatable?

      parts = @content.map(&:with_indifferent_access)
      attachments = parts.select { |part| part[:type].to_s == "image_url" }
                         .filter_map { |part| attachment_source(part.dig(:image_url, :url)) }
      return @content if attachments.empty?

      text = parts.select { |part| part[:type].to_s == "text" }.filter_map { |part| part[:text] }.join("\n")
      RubyLLM::Content.new(text.empty? ? nil : text, attachments)
    end

    private

    def translatable?
      @content.is_a?(Array) &&
        @content.all? { |part| part.is_a?(Hash) } &&
        @content.any? { |part| (part[:type] || part["type"]).to_s == "image_url" }
    end

    # RubyLLM::Attachment recognizes http(s) URLs, file paths, and IO objects, but
    # not base64 `data:` URIs (it would treat one as a filesystem path). Decode
    # those into a binary StringIO, which Attachment handles as an IO source.
    def attachment_source(url)
      return if url.nil? || url.empty?
      return url unless url.start_with?("data:")

      match = url.match(/\Adata:[^;,]*;base64,(.+)\z/m)
      return url unless match

      io = StringIO.new(Base64.decode64(match[1]))
      io.set_encoding(Encoding::BINARY) if io.respond_to?(:set_encoding)
      io
    end
  end
end
