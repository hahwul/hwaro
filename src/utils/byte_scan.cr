# memchr-backed literal scanning.
#
# Crystal's `String#includes?(String)` runs a Rabin-Karp loop in Crystal code
# — one byte per iteration, with a rolling hash update on each — and
# `String#byte_index(Int)` is a plain byte-at-a-time `upto`. Neither reaches
# libc's vectorized `memchr`, and hwaro probes whole documents with short
# ASCII literals constantly: the markdown extension pre-pass alone runs ten
# whole-document `includes?` probes per page, the minifier probes every
# protected tag, and every rendered page gets a NUL scan before minification.
#
# Measured on a 375 KB document (release build, M-series):
#
#   html.byte_index(0)          84.5 µs      html.to_slice.index(0u8)   5.7 µs
#   doc.includes?("~~") (miss)   423 µs      Scan.includes?(doc, "~~")  5.7 µs
#
# The win is entirely from delegating the scan to `memchr` (which `Slice(UInt8)#index`
# routes to) and confirming candidates with `memcmp`, instead of walking bytes
# in Crystal.
#
# These are BYTE searches, which is exactly what the `String` methods they
# replace already do for the boolean answer: UTF-8 is self-synchronizing, so a
# valid multi-byte needle can only match at a character boundary. Callers that
# need a character index must keep using `String#index`.
module Hwaro
  module Utils
    module ByteScan
      extend self

      # True when *byte* occurs anywhere in *str*.
      def byte?(str : String, byte : UInt8) : Bool
        !str.to_slice.index(byte).nil?
      end

      # True when the bytes of *needle* occur anywhere in *haystack*.
      #
      # Equivalent to `haystack.includes?(needle)` for every needle hwaro
      # probes with (`String#includes?` answers the same question over the
      # same bytes; only the index it can also return is character-based).
      def includes?(haystack : String, needle : String) : Bool
        !byte_index(haystack, needle).nil?
      end

      # Byte offset of the first occurrence of *needle* in *haystack*, or nil.
      #
      # `start` is a byte offset. An out-of-range or negative start finds
      # nothing rather than raising — probes run on attacker-shaped content and
      # must not turn a scan into an exception.
      def byte_index(haystack : String, needle : String, start : Int32 = 0) : Int32?
        return if start < 0
        nsize = needle.bytesize
        hsize = haystack.bytesize
        return (start <= hsize ? start : nil) if nsize == 0
        return if nsize > hsize - start

        hay = haystack.to_slice
        first = needle.to_unsafe.value
        return hay.index(first, start) if nsize == 1

        limit = hsize - nsize
        rest = (nsize - 1).to_u64
        needle_rest = needle.to_unsafe + 1
        offset = start
        while offset <= limit
          found = hay.index(first, offset)
          return unless found
          return if found > limit
          if LibC.memcmp((haystack.to_unsafe + found + 1).as(Void*), needle_rest.as(Void*), rest) == 0
            return found
          end
          offset = found + 1
        end
        nil
      end
    end
  end
end
