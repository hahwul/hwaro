# Monkey-patch for Markd's link-destination normalizer — kept here so we
# don't fork the vendored library, mirroring ext/markd_link_label_fix.cr.
#
# Upstream `Markd::Parser::Inline#normalize_uri` runs `URI.decode` over the
# whole destination and then re-encodes it with the RFC 3986 reserved
# characters (`& + , ( ) ' # * ! $ / : ; ? @ =`) kept raw. Every
# percent-escaped reserved character therefore came back out as the raw
# character, which changes what the URL means:
#
#   `https://e.com/s?q=a%26b%3Dc`  =>  `https://e.com/s?q=a&b=c`  (two params)
#   `/a%231.png`                   =>  `/a#1.png`                  (a fragment)
#   `@/n/c%23d.md`                 =>  never matches the page `c#d.md`
#
# CommonMark reference implementations never decode: they keep an existing
# `%XX` and only encode bytes that are not already valid. This keeps the old
# output for everything else — an escape of an unreserved character (`%7E`)
# is still folded to the character, other escapes get upper-case hex, a bare
# `%` becomes `%25`, and non-ASCII bytes are encoded — so only destinations
# that carry an escaped reserved character change.

require "markd"
require "uri"

{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_uri_fix.cr replaces Markd::Parser::Inline#normalize_uri from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Markd::Parser
  class Inline
    def normalize_uri(uri : String)
      bytes = uri.to_slice
      String.build(capacity: uri.bytesize) do |io|
        i = 0
        while i < bytes.size
          byte = bytes[i]
          if byte == '%'.ord && i + 2 < bytes.size && bytes[i + 1].unsafe_chr.hex? && bytes[i + 2].unsafe_chr.hex?
            value = ((bytes[i + 1].unsafe_chr.to_i(16) << 4) | bytes[i + 2].unsafe_chr.to_i(16)).to_u8
            if URI.unreserved?(value)
              io << value.unsafe_chr
            else
              io << '%'
              io << value.to_s(16, upcase: true).rjust(2, '0')
            end
            i += 3
          else
            if URI.unreserved?(byte) || RESERVED_CHARS.includes?(byte.unsafe_chr)
              io << byte.unsafe_chr
            else
              io << '%'
              io << byte.to_s(16, upcase: true).rjust(2, '0')
            end
            i += 1
          end
        end
      end
    end
  end
end
