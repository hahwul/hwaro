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
end
