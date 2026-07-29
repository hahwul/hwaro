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
