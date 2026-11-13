# `{% import %}` / `{% from %}` fixes, as in Jinja2.
#
# 1. `{% import "macros.html" as m %}` pushed the name onto the context's
#    import cycle stack and never popped it, so the SECOND import of the
#    same file in one render failed with `Tag cycle detected: import`: a
#    base layout and the child that extends it each importing their macros,
#    or two imports under different names. The name is popped once the
#    import finishes, so the stack holds only imports still in progress —
#    a real cycle (`a` imports `b` imports `a`) is still reported.
#
# 2. `{% from %}` rendered the file in a fresh environment holding only
#    Crinja's built-ins, so its top-level code could not use hwaro's
#    filters and functions: `{% set v = "x" | slugify %}` in a macro file
#    failed with `no filter with name "slugify" registered`. The child now
#    shares the importing environment's filters, functions, tests, tags
#    and operators.
#
# 3. `{% import "vars.html" as m %}` exposed only the file's macros, so
#    `{{ m.color }}` for a top-level `{% set color = … %}` failed with
#    `m is undefined` (`{% from "vars.html" import color %}` worked).
#    Top-level variables not starting with `_` are now `m.<name>` too.
class Crinja
  # Use *source*'s feature libraries in this environment.
  def __share_features(source : Crinja) : self
    @operators = source.operators
    @filters = source.filters
    @functions = source.functions
    @tags = source.tags
    @tests = source.tests
    self
  end

  def self.new(original : Crinja)
    new(Context.new(original.context), original.config, original.loader).__share_features(original)
  end
end

class Crinja::Tag::Import < Crinja::Tag
  private def interpret(io : IO, renderer : Renderer, tag_node : TagNode)
    env = renderer.env
    parser = ArgumentsParser.new(tag_node.arguments, renderer.env.config)
    name_expr = parser.parse_expression

    context_var = parser.if_identifier "as" do
      parser.next_token
      parser.current_token.value
    end

    parser.close

    include_name = env.evaluate(name_expr).to_s

    stack = env.context.import_path_stack
    stack << include_name

    template = env.get_template(include_name)

    if context_var.nil?
      template.render(env)
    else
      # The file's top level runs in a scope of its own (as upstream's
      # `template.render(child)` did); what it sets there is exported.
      exported = {} of Crinja::Value => Crinja::Value
      env.with_scope do |scope|
        template.render(IO::Memory.new, env)
        scope.session_bindings.each do |key, value|
          exported[Crinja::Value.new(key)] = value unless key.starts_with?('_')
        end
      end

      template.macros.each do |key, value|
        env.context.macros["#{context_var}.#{key}"] = value
      end

      env.context[context_var] = Crinja::Value.new(exported) unless exported.empty?
    end

    stack.pop
  end
end

class Crinja::Tag::From < Crinja::Tag
  private def interpret(io : IO, renderer : Renderer, tag_node : TagNode)
    env = renderer.env
    parser = Parser.new(tag_node.arguments, renderer.env.config)
    source_expression, with_context, imports = parser.parse_from_tag

    template_name = env.evaluate(source_expression).to_s

    child = if with_context
              Crinja.new(env)
            else
              Crinja.new(config: env.config, loader: env.loader).__share_features(env)
            end

    template = child.get_template(template_name)

    template.render(child)

    env.errors += child.errors

    imports.each do |from_name, import_name|
      if template.macros.has_key?(from_name)
        env.context.macros[import_name] = template.macros[from_name]
      elsif child.context.has_key?(from_name)
        env.context[import_name] = child.context[from_name]
      else
        raise RuntimeError.new("Unknown import `#{from_name}` in #{template}").at(tag_node)
      end
    end
  end
end
