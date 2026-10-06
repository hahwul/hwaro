# Monkey-patch for Markd's full-reference-link label check — kept here so we
# don't fork the vendored library, mirroring ext/markd_list_fix.cr.
#
# Upstream `Markd::Parser::Inline#close_bracket` (markd 0.5.0,
# src/markd/parsers/inline.cr:227) ports commonmark.js's
#
#   n = this.parseLinkLabel(); if (n > 2) { reflabel = ... }
#
# but markd's `link_label` returns the label's byte size MINUS ONE (`[a]`
# gives 2, `[]` gives 1), so the ported `> 2` rejects every one-character
# label: `[Crystal][1]` rendered as `[Crystal]` followed by a shortcut link
# `1`. The comparison is `> 1` here; everything else is copied verbatim from
# upstream.

require "markd"

{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_link_label_fix.cr replaces Markd::Parser::Inline#close_bracket verbatim from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Markd::Parser
  class Inline
    private def close_bracket(node : Node)
      title = ""
      dest = ""
      matched = false
      @pos += 1
      start_pos = @pos

      # get last [ or ![
      opener = @brackets
      unless opener
        # no matched opener, just return a literal
        node.append_child(text("]"))
        return true
      end

      unless opener.active
        # no matched opener, just return a literal
        node.append_child(text("]"))
        # take opener off brackets stack
        remove_bracket
        return true
      end

      # If we got here, open is a potential opener
      is_image = opener.image

      # Check to see if we have a link/image
      save_pos = @pos

      # Inline link?
      if char_at?(@pos) == '('
        @pos += 1
        if spnl && (dest = link_destination) &&
           spnl && (char_at?(@pos - 1).try(&.whitespace?) &&
           (title = link_title) || true) && spnl &&
           char_at?(@pos) == ')'
          @pos += 1
          matched = true
        else
          @pos = save_pos
        end
      end

      ref_label = nil
      unless matched
        # Next, see if there's a link label
        before_label = @pos
        label_size = link_label
        if label_size > 1
          ref_label = normalize_reference(@text.byte_slice(before_label, label_size + 1))
        elsif !opener.bracket_after
          # Empty or missing second label means to use the first label as the reference.
          # The reference must not contain a bracket. If we know there's a bracket, we don't even bother checking it.
          byte_count = start_pos - opener.index
          ref_label = byte_count > 0 ? normalize_reference(@text.byte_slice(opener.index, byte_count)) : nil
        end

        if label_size == 0
          # If shortcut reference link, rewind before spaces we skipped.
          @pos = save_pos
        end

        if ref_label && @refmap[ref_label]?
          # lookup rawlabel in refmap
          link = @refmap[ref_label].as(Hash)
          dest = link["destination"] if link["destination"]
          title = link["title"] if link["title"]
          matched = true
        end
      end

      if matched
        child = Node.new(is_image ? Node::Type::Image : Node::Type::Link)
        child.data["destination"] = dest.not_nil! # ameba:disable Lint/NotNil -- verbatim upstream
        child.data["title"] = title || ""

        tmp = opener.node.next?
        while tmp
          next_node = tmp.next?
          tmp.unlink
          child.append_child(tmp)
          tmp = next_node
        end

        node.append_child(child)
        process_emphasis(opener.previous_delimiter)
        remove_bracket
        opener.node.unlink

        unless is_image
          opener = @brackets
          while opener
            opener.active = false unless opener.image
            opener = opener.previous?
          end
        end
      else
        remove_bracket
        @pos = start_pos
        node.append_child(text("]"))
      end

      true
    end
  end
end
