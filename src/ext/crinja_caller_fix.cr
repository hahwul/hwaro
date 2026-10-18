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
end
