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

    # Per-build memo of `DigestUtils.sri_file`, keyed on the file's absolute
    # path, mtime and size: every page printing `asset_integrity()` or an
    # `[assets] sri` tag would otherwise re-read and re-hash the same file.
    # It also remembers each value handed out, so a `[build] hooks.post` that
    # rewrites one of those files can be caught (`stale`). Cleared at every
    # build and serve pass; mutex-guarded for parallel render workers.
    module SriCache
      @@memo = {} of {String, Int64, Int64} => String
      @@emitted = {} of String => String
      @@mutex = Mutex.new

      def self.clear : Nil
        @@mutex.synchronize do
          @@memo.clear
          @@emitted.clear
        end
      end

      # `record: false` hashes without counting the value as handed out (the
      # `--cache` render-inputs probe, which compares and prints nothing).
      def self.sri(path : String, record : Bool = true) : String?
        info = File.info?(path)
        return unless info && info.file?
        absolute = File.expand_path(path)
        key = {absolute, info.modification_time.to_unix_ms, info.size}
        unless sri = @@mutex.synchronize { @@memo[key]? }
          return unless sri = DigestUtils.sri_file(path)
          @@mutex.synchronize { @@memo[key] = sri }
        end
        @@mutex.synchronize { @@emitted[absolute] = sri } if record
        sri
      rescue File::Error
        nil
      end

      # Files whose bytes no longer match the value handed out this build.
      def self.stale : Array(String)
        @@mutex.synchronize { @@emitted.dup }.compact_map do |path, sri|
          path unless DigestUtils.sri_file(path) == sri
        end.sort!
      end
    end
  end
end
