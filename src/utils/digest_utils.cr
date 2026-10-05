# Shared digest helpers for cache fingerprints.

require "base64"
require "digest"
require "openssl"

module Hwaro
  module Utils
    module DigestUtils
      extend self

      # Fold `value` into `digest` with a length prefix so adjacent fields
      # can't produce identical byte streams across boundaries (the
      # "a"+"bc" vs "ab"+"c" ambiguity, which would make two different
      # inputs hash identically and silently fail to invalidate a cache).
      # One implementation for every fingerprint site — template/config
      # checksums, the data-directory digest, and cascade fingerprints —
      # so the prefixing scheme can't drift between cache layers.
      def update_length_prefixed(digest : ::Digest, value : String) : Nil
        digest.update(value.bytesize.to_s)
        digest.update(":")
        digest.update(value)
      end

      # Subresource Integrity value (`sha384-<base64>`) of `data`.
      def sri(data : String | Bytes) : String
        "sha384-" + Base64.strict_encode(OpenSSL::Digest.new("SHA384").update(data).final)
      end

      # `sri` of a file's bytes, or nil when it is not a readable file.
      def sri_file(path : String) : String?
        return unless File.file?(path)
        "sha384-" + Base64.strict_encode(OpenSSL::Digest.new("SHA384").file(path).final)
      rescue File::Error | IO::Error
        nil
      end
    end
  end
end
