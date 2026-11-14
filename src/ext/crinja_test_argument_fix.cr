# A test's argument written without parentheses is one value, as in Jinja2:
# `loop.index is divisibleby 3 and not loop.last` is
# `(loop.index is divisibleby 3) and not loop.last`.
#
# Upstream parsed the whole rest of the expression as the argument, so the
# test above was `divisibleby(3 and not loop.last)`, and
# `x is sameas true or y` / `n is eq 2 and m` silently gave the wrong
# answer. Jinja2 reads a literal, a name or a parenthesized expression plus
# any `.attr` / `[index]` / `(call)` after it (`parse_primary` +
# `parse_postfix`), and no argument at all when the next token is not one
# of those (or is `else` / `or` / `and`). Filters are unchanged.
class Crinja::Parser::ExpressionParser
  private def parse_filter
    left = parse_unary_expression

    loop do
      case current_token.kind
      when Kind::PIPE, Kind::TEST
        is_test = current_token.kind == Kind::TEST
        test_line = current_token.location_start.line

        next_token

        not_location = nil
        if is_test
          if_token Kind::OPERATOR, "not" do
            not_location = current_token.location

            next_token
          end
        end

        identifier = if_token(Kind::NONE) do
          AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
        end || assert_token(Kind::IDENTIFIER) do
          AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
        end

        identifier.location_end = next_token.location

        if is_test
          call = __parse_test_call(identifier, left.location_start.pos, test_line)
          left = AST::TestExpression.new(left, identifier, call.argumentlist, call.keyword_arguments).at(left, call)

          if not_location
            left = AST::UnaryExpression.new("not", left).at(not_location)
          end
        else
          with_parenthesis = false
          if current_token.kind == Kind::LEFT_PAREN
            next_token
            with_parenthesis = true
          elsif config.liquid_compatibility_mode && current_token.kind == Kind::DICT_ASSIGN
            # django/liquid style format `val | filter: arg, arg`
            next_token
          end

          call = parse_call_expression identifier, with_parenthesis: with_parenthesis
          left = AST::FilterExpression.new(left, identifier, call.argumentlist, call.keyword_arguments).at(left, call)
        end
      else
        return left
      end
    end
  end

  private def __parse_test_call(identifier, subject : Int32, line : Int32) : AST::CallExpression
    takes_argument = case current_token.kind
                     when Kind::STRING, Kind::INTEGER, Kind::FLOAT, Kind::BOOL, Kind::NONE,
                          Kind::LEFT_PAREN, Kind::LEFT_BRACKET, Kind::LEFT_CURLY
                       true
                     when Kind::IDENTIFIER
                       !current_token.value.in?("else", "or", "and", "if", "in", "is", "not")
                     else
                       false
                     end
    bare = takes_argument && current_token.kind != Kind::LEFT_PAREN
    arg = current_token.location.pos
    args = [] of AST::ExpressionNode
    args << parse_parenthesis_expression if takes_argument
    if bare && __read_differently_before_1_0?(current_token)
      (@__bare_test_args ||= [] of BareTestArg) << BareTestArg.new(subject, arg, current_token.location.pos, line)
    end
    AST::CallExpression.new(identifier, AST::ExpressionList.new(args),
      Hash(AST::IdentifierLiteral, AST::ExpressionNode).new).at(identifier.location_start, current_token.location)
  end
end

# A warning for the readings the rule above changed silently.
#
# Before 1.0 `page.url is startswith "/blog" ~ "/"` tested against
# `"/blog/"`; it is now `(page.url is startswith "/blog") ~ "/"`, a non-empty
# string, so an `{% if %}` on it is always true. `{{ 3 is divisibleby 1 + 2 }}`
# prints `true2`. When a bare (un-parenthesized) argument is followed by an
# operator that used to belong to the argument and now applies to the test's
# result — `~ + - * / // %`, a filter `|` or another `is` — the build warns
# once per template location (`Template#initialize` below reports;
# `TemplateEngine.warn_template_once` dedupes across render workers and
# pages). `and`, `or`, `not`, `in`, comparisons and `if`/`else` also used to
# be swallowed, but reading them as Jinja2 does is what the rule is for.
# `**` after a bare argument does not parse at all, so it fails loudly.
#
# Parse-time only. `{{ … }}` is parsed when the template loads; a tag keeps
# its argument tokens and parses them when it runs, without knowing its
# template, so `TemplateParser#parse_tag` reads them once more at load time
# (only for tags with an `is` in them) to find the same cases.
class Crinja::Parser::ExpressionParser
  # Byte offsets into the template source (`StreamPosition#pos`): the test's
  # subject, its bare argument, the operator after it and the end of the
  # arithmetic/filter run that operator starts (-1 until that run has been
  # parsed).
  record BareTestArg, subject : Int32, arg : Int32, op : Int32, line : Int32, finish : Int32 = -1 do
    def message(source : String, where : String) : String
      test = BareTestArg.text(source, subject, op)
      rest = BareTestArg.text(source, op, finish)
      joined = BareTestArg.text(source, arg, finish)
      head = BareTestArg.text(source, subject, arg)
      "#{where}:#{line}: '#{test} #{rest}' is read as '(#{test}) #{rest}'; write " \
      "'#{head}(#{joined})' to test against #{joined}, or '(#{test}) #{rest}' to keep this reading."
    end

    def self.text(source : String, from : Int32, to : Int32) : String
      source.byte_slice(from, to - from).strip.gsub(/\s+/, " ")
    end
  end

  CHANGED_AFTER_BARE_TEST_ARG = {"~", "+", "-", "*", "/", "//", "%"}

  @__bare_test_args : Array(BareTestArg)? = nil
  getter __bare_test_args

  private def __read_differently_before_1_0?(token) : Bool
    case token.kind
    when Kind::PIPE, Kind::TEST then true
    when Kind::OPERATOR         then CHANGED_AFTER_BARE_TEST_ARG.includes?(token.value)
    else                             false
    end
  end

  # `~` is the loosest of the operators above (and filters/tests bind
  # tighter), so where it returns is where the misread run ends. Replaces
  # the `parse_operator :tilde` expansion (`previous_def` cannot wrap it).
  private def parse_tilde
    mark = @__bare_test_args.try(&.size) || 0
    node = parse_add_sub
    while current_token.kind == Kind::OPERATOR && current_token.value == Symbol::OP_TILDE
      operator = current_token.value
      next_token
      right = parse_add_sub
      node = AST::BinaryExpression.new(operator, node, right).at(node, right)
    end
    if (found = @__bare_test_args) && found.size > mark
      finish = current_token.location.pos
      (mark...found.size).each do |i|
        found[i] = found[i].copy_with(finish: finish) if found[i].finish < 0
      end
    end
    node
  end

  # Every expression in a tag's argument tokens, for the bare test
  # arguments in them. A tag's own syntax (`set a =`, `for x in`, `ignore
  # missing`) ends or breaks a parse; the next one starts after that token.
  def __probe_bare_test_args : Array(BareTestArg)?
    last = @token_stream.@buffer.size - 1
    while (pos = @token_stream.curr_pos) < last
      begin
        parse_expression
      rescue
      end
      @token_stream.__seek(Math.max(@token_stream.curr_pos, pos) + 1)
    end
    @__bare_test_args.try &.select(&.finish.>=(0))
  end
end

class Crinja::Parser::TokenStream
  def __seek(pos) : Nil
    @curr_pos = pos.to_u32
  end
end

class Crinja::Parser::TemplateParser
  @__tag_bare_test_args : Array(ExpressionParser::BareTestArg)? = nil

  private def parse_tag
    node = previous_def
    if node.is_a?(AST::TagNode) && node.arguments.any?(&.kind.test?)
      if found = Tag::ArgumentsParser.new(node.arguments, config).__probe_bare_test_args
        (@__tag_bare_test_args ||= [] of ExpressionParser::BareTestArg).concat(found)
      end
    end
    node
  end

  def __bare_test_args : Array(ExpressionParser::BareTestArg)?
    found = @expression_parser.__bare_test_args.try(&.select(&.finish.>=(0)))
    tags = @__tag_bare_test_args
    return found unless tags
    return tags unless found
    found + tags
  end
end

class Crinja::Template
  def initialize(@source : String, @env : Crinja = Crinja.new, @name : String = "", @filename : String? = nil, run_parser = true)
    @source = @source.rchop '\n' unless env.config.keep_trailing_newline

    @nodes = AST::NodeList.new([] of AST::TemplateNode, false)

    if run_parser
      parser = begin
        loaded = Parser::TemplateParser.new(@env, @source)
        @nodes = loaded.parse
        loaded
      rescue e : TemplateError
        e.template ||= self
        raise e
      end
      if found = parser.__bare_test_args
        where = @filename || @name.presence || "template"
        found.sort_by! { |f| {f.line, f.op} }
        found.each { |f| Hwaro::Content::Processors::TemplateEngine.warn_template_once(f.message(@source, where)) }
      end
    end
  end
end
