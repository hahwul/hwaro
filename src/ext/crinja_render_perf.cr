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
