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
        return hay.index(needle.to_unsafe.value, start) if nsize == 1

        # memchr for the needle's least common-looking byte — markup or an
        # uppercase letter, else common punctuation, else the first byte
        # (`"aria-hidden"` scans for `-`, not for every `a` in the prose) —
        # confirming each candidate with memcmp.
        bytes = needle.to_slice
        anchor = bytes.index { |byte| anchor_rank(byte) == 2 } || bytes.index { |byte| anchor_rank(byte) == 1 } || 0
        anchor_byte = needle.to_unsafe[anchor]

        limit = hsize - nsize
        offset = start
        while offset <= limit
          found = hay.index(anchor_byte, offset + anchor)
          return unless found
          candidate = found - anchor
          return if candidate > limit
          if LibC.memcmp((haystack.to_unsafe + candidate).as(Void*), needle.to_unsafe.as(Void*), nsize.to_u64) == 0
            return candidate
          end
          offset = candidate + 1
        end
        nil
      end

      # 0: lowercase letter or space (prose), 1: digit or punctuation common
      # in markup text, 2: anything else (`<`, `[`, `{`, `@`, uppercase, …).
      private def anchor_rank(byte : UInt8) : Int32
        char = byte.unsafe_chr
        return 0 if char.ascii_lowercase? || char == ' '
        return 1 if char.ascii_number? || "-=\"/.:;,'_".includes?(char)
        2
      end
    end
  end
end
