# Jinja2 whitespace control (`{%-`, `-%}`, `{{-`, `-}}`, `{#-`, `-#}`).

# The template lexer reuses one Token across delimiters that take no
# expression (`{% else %}`, `{% endif %}`, `{% raw %}`, the text between
# them), and `reset` never cleared the trim flags. A `-` on one delimiter
# leaked onto the next: after `{%- endfor %}` the following `{{ x }}` acted
# as `{{- x }}`, and after `{% if x -%}` the matching `{% endif %}` acted as
# `{% endif -%}` and ate the whitespace after it.
class Crinja::Parser::Token
  def reset(pos)
    previous_def
    @trim_left = false
    @trim_right = false
  end
end

# `-}}` used to reach the parser only through that leak: it read
# `trim_right` after `expect` had already advanced past EXPR_END, i.e. off
# the token that FOLLOWS the print statement. Read it off EXPR_END itself.
class Crinja::Parser::TemplateParser
  private def parse_print_statement
    trim_left = current_token.trim_left
    start_location = current_token.location
    next_token
    expression = @expression_parser.parse(Kind::EXPR_END)

    trim_right = current_token.trim_right
    expect Kind::EXPR_END
    end_location = current_token.location
    set_trim(trim_right, trim_left)

    AST::PrintStatement.new(expression).at(start_location, end_location)
  end

  # A block body starts with no text sibling. Upstream kept the text BEFORE
  # the opening tag as the sibling, so the `{%-` of an empty body's closer
  # (`  {% if x %}{%- endif %}`) trimmed the text outside the block.
  private def parse_node_list(block = false)
    @last_sibling_fixed = nil
    previous_def
  end
end

# A `-` strips ALL whitespace on its side, newlines included. Upstream only
# trimmed the adjacent line (`StringTrimmer.trim` partitions at the first /
# last newline), so `a\n{%- if x %}` kept the newline and
# `{% for … -%}\n  {{ i }}` kept the indent: templates written for Jinja2
# rendered with stray blank lines. A side without `-` keeps the upstream
# trim_blocks / lstrip_blocks handling (hwaro sets neither).
class Crinja::Renderer
  def self.trim_text(node, trim_blocks = false, lstrip_blocks = false)
    string = node.string
    string = string.lstrip if node.trim_left
    string = string.rstrip if node.trim_right

    flag_left = !node.trim_left && trim_blocks && node.left_is_block
    flag_right = !node.trim_right && lstrip_blocks && node.right_is_block
    return string unless flag_left || flag_right

    Crinja::Util::StringTrimmer.trim(string, flag_left, flag_right, node.left_is_block, flag_right)
  end
end
