# Monkey-patch for Markd's inline entity scanner — kept here so we don't
# fork the vendored library, mirroring ext/crinja_resolve_fix.cr and
# ext/tartrazine_mt_fix.cr.
#
# Upstream `Markd::Parser::Inline#entity` treats ANY `&` as the start of a
# named entity and then scans forward without a bound for the next `;`,
# consuming everything in between as one text node. A bare ampersand in
# prose therefore swallowed every inline construct up to the next
# semicolon in the same block:
#
#   `R & D **bold** here; done.` => `R &amp; D **bold** here; done.`
#
# The `**bold**`, `` `code` ``, `[link](/)` between the two characters were
# never parsed — they were emitted verbatim, silently, on a successful
# build. Both `&` and `;` are ordinary English punctuation, so any
# paragraph pairing them was at risk (hwaro#717).
#
# CommonMark 0.31.2 "Entity and numeric character references" specifies the
# bounded grammar we implement instead: a named reference is `&`, a name
# from the HTML5 named-character-reference list, and a trailing `;` — with
# no lenient semicolon-less forms, "because it makes the grammar too
# ambiguous". Anything else is literal text. Markd's own
# ENTITIES_MAPPINGS is exactly that list (2125 names), so membership in it
# is the authority on whether a run is an entity.
#
# Falling through with `false` is the correct literal path: the caller
# (`process_line`) emits the `&` as a one-char text node, bumps the
# position by one, and resumes normal inline parsing on the rest — so the
# markup after the ampersand is parsed, and the renderer escapes the `&`
# to `&amp;` on output.
#
# This also fixes a hard crash: `&;` gave upstream an empty entity name and
# `decode_entity` indexed byte 0 of it, raising IndexError and aborting the
# build. An empty name cannot match the bounded grammar, so it never
# reaches the decoder now.
#
# The numeric branch is left untouched — `Rule::NUMERIC_HTML_ENTITY` is
# already anchored and bounded per the same spec section.
#
# No upstream issue is filed yet (as of 2026-07). Remove when: upstream
# requires a well-formed, list-backed name before consuming the run.

require "markd"

module Markd
  module Rule
    # `&` + HTML5 name + `;`. The length cap covers the longest name in the
    # list ("CounterClockwiseContourIntegral", 31 chars); the mapping lookup
    # below is what actually decides validity.
    NAMED_HTML_ENTITY = /^&[a-zA-Z][a-zA-Z0-9]{1,31};/
  end
end

module Markd::Parser
  class Inline
    private def entity(node : Node)
      return false unless char_at?(@pos) == '&'

      if char_at?(@pos + 1) == '#'
        matched = match(Rule::NUMERIC_HTML_ENTITY) || return false
        body = matched.byte_slice(1, matched.bytesize - 2)
      else
        start_pos = @pos
        matched = match(Rule::NAMED_HTML_ENTITY) || return false
        body = matched.byte_slice(1, matched.bytesize - 2)
        # Not a real HTML5 name: rewind so the `&` is re-emitted as literal
        # text and the rest of the run goes back through inline parsing.
        unless Markd::HTMLEntities::ENTITIES_MAPPINGS.has_key?(body)
          @pos = start_pos
          return false
        end
      end

      node.append_child(text(HTML.decode_entity(body)))
      true
    end
  end
end

# === Decoder: the entity path used OUTSIDE inline body text ================
#
# Link destinations, link titles, and fence info strings do not go through
# the scanner above — they are decoded wholesale by
# `Markd::HTMLEntities::Decoder.decode` (via `Markd::Utils
# .decode_entities_string`). That decoder has three defects of its own,
# found while auditing the neighbourhood of hwaro#717. All three are fixed
# by overriding the three methods below; `Decoder::REGEX` itself cannot be
# reassigned from a reopened module, so `decode` switches to the strict
# pattern defined here and the old constant simply goes unused.
#
# 1. CRASH. `REGEX` accepts `#\d+;?` with no digit bound and `decode_entity`
#    then calls `.to_i` on the run, so a long enough reference raises
#    `ArgumentError: Invalid Int32` and aborts the build:
#      `[t](/a?x=&#99999999999999999999;)` — link destination
#      `[t](/a "&#99999999999999999999;")` — link title
#      "```&#99999999999999999999;"       — fence info string
#    hwaro's own importer already guards this with `to_i?` (see
#    html_to_markdown.cr); the vendored decoder does not.
#
# 2. MIS-DECODE. `REGEX` makes the trailing `;` optional, but `decode`
#    unconditionally strips the FIRST AND LAST character before decoding.
#    A semicolon-less reference therefore loses its final digit and decodes
#    the wrong codepoint entirely: `&#38` -> U+0003, `&#100` -> newline.
#    CommonMark does not recognize semicolon-less references at all, so the
#    strict pattern leaves them as literal text.
#
# 3. ASTRAL PLANE. `decode_codepoint` range-checks against `0x10FFF`
#    (69_631) where Unicode's maximum is `0x10FFFF` (1_114_111) — one hex
#    digit short. EVERY reference above U+10FFF decoded to U+FFFD: all
#    emoji (`&#x1F600;`, `&#128512;`), CJK Ext B and beyond, math
#    alphanumerics, musical symbols. This one also reaches ordinary body
#    text through the scanner above.
#
# Remove when: upstream requires `;`, bounds the digit run, parses with
# `to_i?`, and range-checks against 0x10FFFF.

module Markd::HTMLEntities
  module Decoder
    # The CommonMark 0.31.2 grammar, matching Rule::NAMED_HTML_ENTITY and
    # Rule::NUMERIC_HTML_ENTITY above: `;` required, digits bounded.
    STRICT_REGEX = /&(?:[a-zA-Z][a-zA-Z0-9]{1,31}|#[Xx][0-9a-fA-F]{1,6}|#[0-9]{1,7});/

    def self.decode(source)
      source.gsub(STRICT_REGEX) do |chars|
        # Safe now that the pattern guarantees a leading `&` and trailing `;`
        # with a non-empty body between them.
        decode_entity(chars[1..-2])
      end
    end

    def self.decode_entity(chars)
      return "&;" if chars.empty?

      if chars[0] == '#'
        if chars.size > 2 && chars[1].downcase == 'x'
          # to_i?, not to_i: never raise on a caller that skipped the pattern.
          if codepoint = chars[2..-1].to_i?(16)
            return decode_codepoint(codepoint)
          end
        elsif chars.size > 1
          if codepoint = chars[1..-1].to_i?(10)
            return decode_codepoint(codepoint)
          end
        end
      elsif resolved_entity = Markd::HTMLEntities::ENTITIES_MAPPINGS[chars]?
        return resolved_entity
      end

      "&#{chars};"
    end

    def self.decode_codepoint(codepoint)
      # 0x10FFFF, not 0x10FFF — see defect 3 above.
      return "�" if (0xD800 <= codepoint <= 0xDFFF) || codepoint > 0x10FFFF

      if decoded = Markd::HTMLEntities::DECODE_MAPPINGS[codepoint]?
        codepoint = decoded
      end

      codepoint.unsafe_chr
    end
  end
end
