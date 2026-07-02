# Shared digest helpers for cache fingerprints.

require "digest"

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
    end
  end
end
