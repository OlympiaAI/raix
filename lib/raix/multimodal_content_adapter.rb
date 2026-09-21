# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"
require "base64"
require "stringio"

module Raix
  # Translates OpenAI-style structured content arrays into the pieces RubyLLM
  # wants: a String of text, a list of attachment sources, and whether the
  # message ends a prompt cache prefix.
  #
  # RubyLLM only accepts String content, so a message whose content is an array
  # of `{ type: "text" }` / `{ type: "image_url" }` parts has to be taken apart
  # before it can be added to a chat. Images become attachments, text parts are
  # joined, and a part carrying `cache_control` marks the message as a cache
  # boundary. See https://github.com/OlympiaAI/raix/issues/51
  #
  # Content that is not an array of hashes passes through untouched, so plain
  # text completions are unaffected.
  class MultimodalContentAdapter
    # `cache_ttl` carries the first `cache_control.ttl` seen, so the caller can
    # pass it to RubyLLM's chat-level caching options. RubyLLM marks cache
    # boundaries per message, so a boundary inside a content array lands at
    # the end of that message.
    Result = Struct.new(:content, :attachments, :cache_boundary, :cache_ttl) do
      alias_method :cache_boundary?, :cache_boundary
    end

    # @return [Result]
    def self.translate(content)
      new(content).translate
    end

    def initialize(content)
      @content = content
    end

    def translate
      return Result.new(@content, [], false) unless structured?

      parts = @content.map(&:with_indifferent_access)

      attachments = parts.select { |part| part[:type].to_s == "image_url" }
                         .filter_map { |part| attachment_for(part.dig(:image_url, :url)) }
      text = parts.select { |part| part[:type].to_s == "text" }.filter_map { |part| part[:text] }.join("\n")
      cache_controls = parts.filter_map { |part| part[:cache_control].presence }
      cache_ttl = cache_controls.filter_map { |control| control.is_a?(Hash) ? control[:ttl] : nil }.first

      Result.new(text.empty? ? nil : text, attachments, cache_controls.any?, cache_ttl)
    end

    private

    # An empty array counts: dynamically assembled content whose parts were all
    # filtered out becomes nil content, which ChatCompletion sends as "".
    def structured?
      @content.is_a?(Array) && @content.all? { |part| part.is_a?(Hash) }
    end

    # OpenAI's `image_url` accepts an http(s) URL or a base64 `data:` URI, and
    # that is all this adapter forwards. RubyLLM::Attachment would treat any
    # other String as a filesystem path to read, so bare paths are skipped
    # rather than passed through.
    #
    # RubyLLM does not decode `data:` URIs itself; those become a binary
    # StringIO, and RubyLLM sniffs the media type from the bytes.
    def attachment_for(url)
      return if url.nil? || url.empty?
      return url if url.match?(%r{\Ahttps?://}i)

      match = url.match(/\Adata:[^;,]*;base64,(.+)\z/mi)
      return unless match

      io = StringIO.new(Base64.decode64(match[1]))
      io.set_encoding(Encoding::BINARY) if io.respond_to?(:set_encoding)
      io
    end
  end
end
