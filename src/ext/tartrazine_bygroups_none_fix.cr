# Monkey-patch for Tartrazine's `<bygroups>` parsing — kept here so we don't
# fork the vendored library, like ext/tartrazine_mt_fix.cr.
#
# Pygments/Chroma lexer XML marks a capture group that must emit nothing with
# a bare `None` text node between the `<token>` elements:
#
#   <rule pattern="(end(case|unless|if))(\s*)(%\})">
#     <bygroups><token type="KeywordReserved"/>None<token .../><token .../></bygroups>
#
# `Tartrazine::Action#initialize` only collects ELEMENT children, so the
# `None` vanished and the token list ended up one entry short and shifted
# against the regex groups: group 2 (`if`) took the whitespace token, group 3
# the punctuation token and group 4 (`%}`) none at all. A ```liquid fence
# containing `{% endif %}` rendered as `{% endifif ` — the closing `%}` lost
# and the tag name doubled.
#
# A `None` node now becomes a placeholder action that consumes its group and
# emits nothing (`<pop depth="0"/>` is a no-op). Only LiquidLexer.xml uses
# the construct in the lexers bundled today.
#
# Remove when: upstream's Action#initialize keeps `None` placeholders.

require "tartrazine"

struct Tartrazine::Action
  # Parsed once; the placeholder carries no per-use state.
  HWARO_SKIP_XML = XML.parse(%(<pop depth="0"/>)).first_element_child.as(XML::Node)

  def initialize(t : String, xml : XML::Node?)
    previous_def
    return unless xml && @type.bygroups?
    return unless xml.children.any? { |node| node.text? && node.content.strip == "None" }

    elements = @actions.dup
    @actions.clear
    index = 0
    xml.children.each do |node|
      if node.element?
        @actions << elements[index]
        index += 1
      elsif node.text? && node.content.strip == "None"
        @actions << Tartrazine::Action.new("pop", HWARO_SKIP_XML)
      end
    end
  end
end
