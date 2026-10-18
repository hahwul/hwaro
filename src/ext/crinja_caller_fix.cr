# `caller` inside a macro invoked by `{% call %}`, as in Jinja2.
#
# Upstream registered the call block as a context-wide MACRO named
# `caller`: `{{ caller() }}` worked, but `caller` was no variable, so the
# usual optional-body idioms (`{% if caller %}`, `caller() if caller else ""`,
# `caller is defined`) always took the no-caller branch and dropped the call
# block's body. The registration also outlived the call, so a later plain
# `{{ m() }}` still rendered the previous call block. The block is now bound
# as a `caller` variable for the duration of the call only.
class Crinja::Tag::Call < Crinja::Tag
  def interpret_output(renderer : Renderer, tag_node : TagNode)
    env = renderer.env
    parser = Parser.new(tag_node.arguments, renderer.env.config)
    defaults, call = parser.parse_call_tag

    instance = Tag::Macro::MacroFunction.new "caller", tag_node.block, renderer, caller: true
    defaults.each do |key, value|
      instance.defaults[key] = value.is_a?(AST::ExpressionNode) ? env.evaluate(value) : Value.new(value)
    end

    output = env.with_scope({"caller" => Value.new(instance)}) { env.evaluate(call).to_s }
    Renderer::RenderedOutput.new(output)
  end

  # The called macro is any call expression, as in Jinja2, so a macro
  # imported under a namespace works: `{% call forms.dialog() %}`. Upstream
  # read a bare name and failed with "Expected LEFT_PAREN, got POINT".
  private class Parser < ArgumentsParser
    def parse_call_tag
      defaults = Hash(String, AST::ExpressionNode?).new

      if_token Kind::LEFT_PAREN do
        location = current_token.location
        next_token
        args = parse_call_expression(AST::IdentifierLiteral.new("call").at(location))

        args.argumentlist.children.each do |arg_expr|
          if (arg = arg_expr).is_a?(AST::IdentifierLiteral)
            defaults[arg.name] = nil
          else
            raise TemplateSyntaxError.new(arg_expr, "Invalid statement #{arg_expr} in call def")
          end
        end

        args.keyword_arguments.each do |arg, value|
          defaults[arg.name] = value
        end
      end

      call = parse_expression
      close

      {defaults, call}
    end
  end
end
