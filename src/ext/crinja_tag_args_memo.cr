# Parse tag arguments once per template, not once per execution.
#
# Crinja parses `{{ … }}` expressions when the template loads, but a tag keeps
# its arguments as raw tokens and every tag implementation runs
# `ArgumentsParser` on them each time the tag executes. A
# `{% if loop.index <= 10 %}` inside a loop over 5,000 pages, rendered on each
# of those pages, is parsed 25 million times; on the ssg-benchmark `heavy`
# corpus expression parsing was ~40% of `If#evaluate_node` (issue #883).
#
# The parse result is a pure function of the tag's tokens and the env config,
# both fixed for the template's lifetime, and nothing mutates an expression
# AST while evaluating it — so the hot tags memoize their parsed arguments on
# the TagNode, the way `{{ … }}` already holds its parsed expression.
# Concurrent first executions (templates compiled outside an env, e.g. render
# hooks) can race on the memo, but both sides store an equivalent, fully built
# value. Every memo is a reference (an AST node, a Hash, a Memo box), so it is
# published with one pointer-sized store and a reader sees nil or a complete
# value, never a torn multi-word Tuple.
# Parse errors are raised before anything is stored, so a broken tag still
# raises on every execution, exactly as before.
#
# Deliberately not memoized:
# - `filter`: its parse builds a ValuePlaceholder that each execution mutates.
# - tags that run once per render (extends, block, import, from, macro, call,
#   autoescape, raw): parsing them is noise next to the render itself.
#
# This file must load before ext patches that wrap these tags with
# `previous_def` (crinja_include_depth_fix.cr), so their wrappers call the
# memoizing body.

class Crinja::AST::TagNode
  # `if`/`elif` condition, `do` expression.
  property __args_expr : Crinja::AST::ExpressionNode?
  # `set a = …, b = …` / `with a = …` assignments, in source order.
  property __args_keywords : Hash(Crinja::AST::IdentifierLiteral, Crinja::AST::ExpressionNode)?
  # `for`: {item vars, collection, if condition, recursive}.
  property __args_for : Crinja::Tag::Memo(::Tuple(Array(String), Crinja::AST::ExpressionNode, Crinja::AST::ExpressionNode?, Bool))?
  # `include`: {source, ignore missing, with context}.
  property __args_include : Crinja::Tag::Memo(::Tuple(Crinja::AST::ExpressionNode, Bool, Bool))?
end

class Crinja::Tag
  # Boxes a parsed-argument Tuple so the TagNode memo is a reference.
  class Memo(T)
    getter value : T

    def initialize(@value : T)
    end
  end
end

class Crinja::Tag::If < Crinja::Tag
  def evaluate_node(tag_node, env : Crinja)
    return true if tag_node.name == "else"

    env.evaluator.value(self.class.parsed_condition(tag_node, env.config)).truthy?
  end

  # The condition of an `if`/`elif` node. Also read by the for-loop
  # closed-body analysis in crinja_render_perf.cr.
  def self.parsed_condition(tag_node : TagNode, config : Config) : AST::ExpressionNode
    tag_node.__args_expr ||= begin
      arguments = ArgumentsParser.new(tag_node.arguments, config)
      parsed = arguments.parse_expression

      if parsed.is_a?(AST::Empty)
        raise TemplateSyntaxError.new(tag_node, "#{tag_node.name} tag missing condition")
      end

      arguments.close
      parsed
    end
  end
end

class Crinja::Tag::Do < Crinja::Tag
  def evaluate_node(tag_node, env : Crinja)
    expression = tag_node.__args_expr ||= begin
      arguments = ArgumentsParser.new(tag_node.arguments, env.config)
      parsed = arguments.parse_expression
      arguments.close
      parsed
    end

    env.evaluate(expression)
  end
end

class Crinja::Tag::Set < Crinja::Tag
  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    env = renderer.env

    if tag_node.arguments.size == 2
      # IDENTIFIER + EOF: block assignment. Nothing to parse beyond the name.
      args = ArgumentsParser.new(tag_node.arguments, env.config)
      name = args.current_token.value
      args.next_token
      value = renderer.render(tag_node.block).value
      env.context[name] = SafeString.new(value)
      args.close
    else
      assignments = tag_node.__args_keywords ||= begin
        args = ArgumentsParser.new(tag_node.arguments, env.config)
        parsed = args.parse_keyword_list
        args.close
        parsed
      end

      assignments.each do |identifier, expr|
        env.context[identifier.name] = env.evaluate(expr)
      end
    end
  end
end

class Crinja::Tag::With < Crinja::Tag
  def interpret_output(renderer : Crinja::Renderer, tag_node : TagNode)
    env = renderer.env
    assignments = tag_node.__args_keywords ||= Parser.new(tag_node.arguments, env.config).parse_with_tag_arguments

    var_defs = Variables.new
    assignments.each do |variable, expression|
      var_defs[variable.name] = env.evaluate(expression)
    end

    env.with_scope(var_defs) do
      renderer.render(tag_node.block)
    end
  end
end

class Crinja::Tag::For < Crinja::Tag
  # Called by `interpret_output` in crinja_render_perf.cr.
  def parsed_for_arguments(tag_node : TagNode, config : Config)
    (tag_node.__args_for ||= Memo.new(Parser.new(tag_node.arguments, config).parse_for_tag)).value
  end
end

class Crinja::Tag::Include < Crinja::Tag
  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    env = renderer.env
    source_expression, ignore_missing, with_context =
      (tag_node.__args_include ||= Memo.new(Parser.new(tag_node.arguments, env.config).parse_include_tag)).value

    begin
      source = env.evaluate(source_expression)
    rescue error : UndefinedError
      if env.config.liquid_compatibility_mode
        # enables use of `{% include file.name %}` => `source = "file.name"`
        source = Value.new(String.build do |str|
          Visitor::Source.new(str).visit(tag_node.arguments)
        end.strip)
      else
        raise error
      end
    end

    if source.iterable?
      include_name = source.map &.to_s
    else
      include_name = source.to_s
    end

    context = env.global_context unless with_context

    begin
      env.logger.debug { "loading include #{include_name}" }
      template = env.get_template(include_name)
      template.render(io, context)
    rescue error : TemplateNotFoundError
      raise error unless ignore_missing
    end
  end
end
