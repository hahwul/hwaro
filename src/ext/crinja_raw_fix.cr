# `{% raw %}` whitespace control and closer detection, as in Jinja2.
#
# Upstream's raw scanner only recognised a closer spelled `{%` + spaces +
# `endraw`, so `{%- endraw %}` was never seen and the template failed with
# "Unclosed tag, missing: endraw" — while hwaro's own raw-block masking
# (ShortcodeProcessor::RAW_BLOCK_RE) accepts that form. It also stopped at
# any `{% endraw…` prefix (`{% endrawx %}`, `'{% endraw'` inside an example),
# where Jinja2 requires the tag to close with `%}` / `-%}`.
#
# And the raw tag printed its content untrimmed, ignoring `{% raw -%}` and
# `{%- endraw %}`; it now trims like any other text node.
class Crinja::Parser::TemplateLexer
  def consume_raw
    @buffer.clear

    loop do
      char = current_char
      break if char == Char::ZERO
      break if char == Symbol::PREFIX && peek_char == Symbol::TAG && raw_end_ahead?

      @buffer << char
      next_char
    end

    @buffer.to_s
  end

  # Is the `{%` at the cursor `{%-? endraw -?%}` (any inner whitespace)?
  private def raw_end_ahead? : Bool
    offset = 2
    offset += 1 if peek_char(offset) == Symbol::TRIM_WHITESPACE
    offset = peek_for_whitespace_offset(offset)
    Symbol::RAW_END.each_char do |c|
      return false unless peek_char(offset) == c
      offset += 1
    end
    offset = peek_for_whitespace_offset(offset)
    offset += 1 if peek_char(offset) == Symbol::TRIM_WHITESPACE
    peek_char(offset) == Symbol::TAG && peek_char(offset + 1) == Symbol::POSTFIX
  end
end

class Crinja::Tag::Raw
  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    ArgumentsParser.new(tag_node.arguments, renderer.env.config).close
    if (fixed = tag_node.block.children.first).is_a?(AST::FixedString)
      config = renderer.env.config
      io << Crinja::Renderer.trim_text(fixed, config.trim_blocks, config.lstrip_blocks)
    else
      raise TemplateSyntaxError.new(tag_node, "raw tag expexts exactly one fixed content node inside")
    end
  end
end
