# Render-path performance patches for the vendored Crinja runtime — kept
# here so we don't fork the library, mirroring ext/crinja_resolve_fix.cr.
#
# All three patches are byte-compat: they change how the rendered string is
# assembled, never which bytes come out. Verified by diff -r of full output
# trees on the harsh-5000 and public-5000 benchmark corpora.
#
# Motivation (sampled on an M4 Max, harsh-5000 corpus, release build): with
# templates that iterate site-wide collections, render time is dominated by
# per-iteration allocations inside Crinja — a String.build copy per printed
# expression, a re-trim of every static text fragment on every iteration,
# and an intermediate String per nested OutputList when the page is joined.

class Crinja::Renderer
  # === 1. PrintStatement fast path ======================================
  # Upstream stringifies every printed value through Finalizer via
  # String.build, which copies the string even in the overwhelmingly common
  # case: a String (or SafeString) value with autoescape disabled, where
  # Finalizer writes the bytes verbatim (`quote` only adds quotes inside
  # structs, never at the top level). Return the string itself instead of
  # copying it. Non-string values and autoescaped output keep the original
  # path.
  def render(node : AST::PrintStatement)
    expr = node.expression
    if expr.is_a?(AST::CallExpression) &&
       (id = expr.identifier) && id.is_a?(AST::IdentifierLiteral) &&
       id.as(AST::IdentifierLiteral).name == "super"
      return render_super(expr.as(AST::CallExpression))
    end

    result = env.evaluate(expr)

    raw = result.raw
    case raw
    when SafeString
      # SafeString is never escaped; #to_s returns the wrapped String.
      return RenderedOutput.new(raw.to_s)
    when String
      return RenderedOutput.new(raw) unless env.context.autoescape?
    end

    RenderedOutput.new env.stringify(result)
  rescue ex : Crinja::Error
    ex.at(node) unless ex.has_location?
    raise ex
  end

  # === 2. FixedString trim memoization ==================================
  # Static template text is re-trimmed (allocating a fresh String) every
  # time its node renders — for a loop body that means once per iteration,
  # for a listing template once per page per item. The trim result depends
  # only on the node and the two config flags, so cache the RenderedOutput
  # on the node keyed by those flags. RenderedOutput is immutable, so
  # sharing one instance across OutputLists (and across fibers — the write
  # is an idempotent benign race) is safe.
  def render(node : AST::FixedString)
    trim_blocks = env.config.trim_blocks
    lstrip_blocks = env.config.lstrip_blocks

    if (cached = node.__trim_cache) && cached[0] == trim_blocks && cached[1] == lstrip_blocks
      return cached[2]
    end

    output = RenderedOutput.new Crinja::Renderer.trim_text(node, trim_blocks, lstrip_blocks)
    node.__trim_cache = {trim_blocks, lstrip_blocks, output}
    output
  rescue ex : Crinja::Error
    ex.at(node) unless ex.has_location?
    raise ex
  end

  # === 3. Streaming OutputList join =====================================
  # Upstream joins nested lists with `io << node.value`, which builds the
  # entire nested subtree (e.g. a for-loop's whole output) into an
  # intermediate String before copying it into the parent — every level of
  # nesting re-copies the page. Recurse with the IO instead so bytes are
  # written exactly once. BlockOutput#value must still be called eagerly
  # (it raises on unresolved placeholders), which `else` covers.
  class OutputList < Output
    def value(io : IO)
      nodes.each do |node|
        if node.is_a?(OutputList)
          node.value(io)
        else
          io << node.value
        end
      end
    end

    # === 4. Block-free subtree pruning ==================================
    # `resolve_block_stubs` walks the entire nested output tree of every
    # rendered page via `each_block`, even though block placeholders only
    # exist where `{% block %}` tags rendered — never inside a for-loop's
    # thousands of per-iteration lists. Track transitively whether a list
    # (or any descendant) holds a BlockOutput at append time, and skip
    # block-free subtrees during the walk. Appends only happen while a
    # subtree is being built (outputs are returned upward fully formed),
    # so the flag is final by the time each_block runs.
    @has_blocks = false

    def has_blocks? : Bool
      @has_blocks
    end

    def <<(output)
      nodes << output.not_nil! # ameba:disable Lint/NotNil -- mirrors the upstream `<<`

      case output
      when BlockOutput
        blocks << output
        @has_blocks = true
      when OutputList
        @has_blocks ||= output.has_blocks?
      end
    end

    def each_block(&iterator : BlockOutput -> _)
      return unless @has_blocks

      blocks.each do |block|
        iterator.call(block)
      end

      nodes.each do |node|
        if node.is_a?(OutputList)
          node.each_block(&iterator)
        end
      end
    end
  end
end

class Crinja::AST::FixedString
  # See "FixedString trim memoization" in ext/crinja_render_perf.cr.
  # `::Tuple` — inside the Crinja namespace a bare `Tuple` resolves to
  # `Crinja::Tuple`, which is not generic.
  property __trim_cache : ::Tuple(Bool, Bool, Crinja::Renderer::RenderedOutput)?
end

# === 5+6. Loop-invariant fragment caching & iteration scope reuse =========
#
# Both patches key off the same static property of a for-loop, which we call
# a *closed* body: every identifier the body (and the optional `if`
# condition) reads is bound by the loop itself (the item variables or
# `loop`), the body contains no nested tags, and no calls/filters/tests.
# Such a body can neither observe per-page state nor capture the iteration
# context (no `{% block scoped %}`, no macro definitions, no callables), so:
#
# 5. Fragment cache — the loop's entire output is a pure function of
#    (loop AST node, collection contents, autoescape). Listing templates
#    like `{% for p in site.pages %}<li>{{ p.title }}</li>{% endfor %}`
#    re-render byte-identical output once per page; on the harsh-5000
#    corpus that loop alone accounts for most of the render phase. Cache
#    the flattened output per (tag node, collection object, autoescape) on
#    the environment. Correctness leans on two facts: hwaro converts
#    site/section collections to Crinja arrays once per build (stable
#    object identity ⇒ stable contents — the site is frozen during
#    render), and each render worker owns its env exclusively (no
#    concurrent mutation; the env — and so the cache — lives for a single
#    render pass). Entries pin their tag node and collection array, so an
#    object_id can never be recycled into a false hit. The cache is
#    size-capped: loops over per-page collections (`{% for t in p.tags %}`)
#    insert entries that never hit again, so past the cap we render
#    normally instead of inserting.
#
# 6. Scope reuse — upstream run_loop allocates a fresh Context (scope Hash,
#    macros Hash, four CallStacks) plus a bindings Hash per iteration. For
#    a closed body nothing can retain the iteration context beyond its
#    iteration, so one Context reused across iterations (item vars simply
#    overwritten by unpack) is observationally identical. Non-closed
#    bodies keep the allocating path.
#
# Byte-compat verified like patches 1-4: diff -r of full output trees on
# harsh-5000, public-5000 and docs, plus a loop-shape torture site.
class Crinja
  # Fragment cache: {tag node id, collection array id, autoescape} →
  # flattened output. Lazy so envs that never render a cacheable loop pay
  # nothing.
  getter __for_fragment_cache : Hash(::Tuple(UInt64, UInt64, Bool), Crinja::Tag::For::FragmentEntry) do
    Hash(::Tuple(UInt64, UInt64, Bool), Crinja::Tag::For::FragmentEntry).new
  end
end

class Crinja::AST::TagNode
  # Memoized closed-body verdict for for-loops (see ext/crinja_render_perf.cr).
  # The verdict is a pure function of this node's own subtree and arguments,
  # so computing it once is safe.
  property __closed_body : Bool?
end

class Crinja::Tag::For
  # Insert-stop cap for the fragment cache. Site-wide listing loops need a
  # handful of entries; loops over per-page collections would otherwise
  # insert one dead entry per page.
  FRAGMENT_CACHE_MAX = 128

  # An entry pins `tag` and `collection` so their object_ids stay valid for
  # the cache's lifetime (a single render pass).
  record FragmentEntry,
    tag : Crinja::AST::TagNode,
    collection : Array(Crinja::Value),
    output : Crinja::Renderer::RenderedOutput

  def interpret_output(renderer : Renderer, tag_node : TagNode)
    env = renderer.env
    parser = Parser.new(tag_node.arguments, renderer.env.config)
    item_vars, collection_expr, if_expr, recursive = parser.parse_for_tag

    runner = Runner.new(renderer, tag_node, item_vars)

    collection = env.evaluator.value(collection_expr)

    closed = !recursive && closed_loop?(tag_node, item_vars, if_expr)

    cache = nil
    key = {0_u64, 0_u64, false}
    raw = collection.raw
    if closed && raw.is_a?(Array(Value))
      key = {tag_node.object_id, raw.object_id, env.context.autoescape?}
      cache = env.__for_fragment_cache
      if entry = cache[key]?
        return entry.output
      end
      cache = nil if cache.size >= FRAGMENT_CACHE_MAX
    end

    if if_expr
      collection = ConditionalIterator.new(collection.each, if_expr, env, item_vars)
    end

    if recursive
      looper = ForLoop::Recursive.new runner, collection
    else
      looper = ForLoop.new collection
    end

    result = closed ? runner.run_loop_with_reused_scope(looper) : runner.run_loop(looper)

    output = if looper.index == 0
               # no items were processed, render else branch (a closed body
               # has no `else` tag, so for `closed` this renders empty —
               # deterministic, and safe to cache like any other output)
               runner.render_else
             else
               result
             end

    if cache
      flat = Renderer::RenderedOutput.new(output.value)
      cache[key] = FragmentEntry.new(tag_node, raw.as(Array(Value)), flat)
      return flat
    end

    output
  end

  # A loop is closed when its body and `if` condition read nothing but the
  # loop's own bindings. Memoized on the tag node.
  private def closed_loop?(tag_node : TagNode, item_vars : Array(String), if_expr : AST::ExpressionNode?) : Bool
    cached = tag_node.__closed_body
    return cached unless cached.nil?

    bound = item_vars.dup << LOOP_VARIABLE
    verdict = closed_nodes?(tag_node.block.children, bound) &&
              (if_expr.nil? || closed_expression?(if_expr, bound))
    tag_node.__closed_body = verdict
    verdict
  end

  private def closed_nodes?(nodes : Array(AST::TemplateNode), bound : Array(String)) : Bool
    nodes.all? do |node|
      case node
      when AST::FixedString, AST::Note, AST::EndTagNode
        true
      when AST::NodeList
        closed_nodes?(node.children, bound)
      when AST::PrintStatement
        closed_expression?(node.expression, bound)
      else
        # Any nested tag (if/for/set/block/macro/filter/…) disqualifies:
        # tags can bind or mutate state, capture the context, or carry
        # unparsed argument tokens we can't analyze.
        false
      end
    end
  end

  private def closed_expression?(expr : AST::ExpressionNode, bound : Array(String)) : Bool
    case expr
    when AST::IdentifierLiteral
      bound.includes?(expr.name)
    when AST::StringLiteral, AST::IntegerLiteral, AST::FloatLiteral,
         AST::BooleanLiteral, AST::NullLiteral, AST::Empty
      true
    when AST::MemberExpression
      # `.member` names are not variable reads — only the receiver is.
      closed_expression?(expr.identifier, bound)
    when AST::IndexExpression
      closed_expression?(expr.identifier, bound) && closed_expression?(expr.argument, bound)
    when AST::BinaryExpression
      closed_expression?(expr.left, bound) && closed_expression?(expr.right, bound)
    when AST::ComparisonExpression
      closed_expression?(expr.left, bound) && closed_expression?(expr.right, bound)
    when AST::UnaryExpression
      closed_expression?(expr.right, bound)
    when AST::SplashOperator
      closed_expression?(expr.right, bound)
    when AST::Expressions, AST::ExpressionList, AST::IdentifierList,
         AST::ArrayLiteral, AST::TupleLiteral
      expr.children.all? { |child| closed_expression?(child, bound) }
    when AST::DictLiteral
      expr.children.all? { |k, v| closed_expression?(k, bound) && closed_expression?(v, bound) }
    else
      # CallExpression / FilterExpression / TestExpression may reach
      # functions, filters or macros (free names, possibly impure).
      # ValuePlaceholder is mutated by the filter-tag machinery. Unknown
      # node kinds fail closed.
      false
    end
  end

  class Runner
    # Allocation-light run_loop for closed bodies: one Context for the
    # whole loop instead of one per iteration. `unpack` overwrites the
    # item variables in place; nothing in a closed body can retain the
    # context beyond its iteration (no blocks, macros or callables), and
    # the iterator advances outside the scope exactly as upstream does.
    def run_loop_with_reused_scope(looper)
      env = @renderer.env
      iteration_scope = Context.new(env.context)
      iteration_scope[LOOP_VARIABLE] = Value.new(looper)

      Renderer::OutputList.new.tap do |output|
        looper.each do |value|
          env.with_scope(iteration_scope) do |context|
            context.unpack @item_vars, value
            output << render_children
          end
        end
      end
    end
  end
end
