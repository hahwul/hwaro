# Monkey-patch for unbounded template recursion through `{% from %}` and
# macro calls — the two paths ext/crinja_include_depth_fix.cr does not see.
#
# - A macro that calls itself without a base case
#   (`{% macro f(n) %}{{ f(n+1) }}{% endmacro %}{{ f(1) }}`) recurses in
#   `Crinja::Tag::Macro::MacroFunction#call` (crinja 0.9.0,
#   src/lib/tag/macro.cr:110), which has no depth limit; the `macro_stack`
#   crinja allocates is never used.
# - A `{% from %}` cycle (`page.html` imports from `b.html`, which imports
#   from `page.html`) renders each target in a FRESH `Crinja.new(...)`
#   (src/lib/tag/from.cr:16-24), so neither crinja's `import_path_stack` nor
#   the env-level include chain carries across the hop.
#
# Both died with `Stack overflow (e.g., infinite or very deep recursion)`,
# which Crystal cannot rescue: `hwaro build` aborted with a raw backtrace and
# `hwaro serve` was killed by the first rebuild that rendered the template.
#
# The guard measures the stack that is actually left rather than counting
# levels: what one macro level costs depends on its body (a level wrapped in
# ten nested for/if tags overflowed an 8 MB stack before a 200-level count
# tripped), while a count low enough for that rejects terminating recursion
# a few hundred levels deep that renders fine. Crystal records each fiber's
# stack bounds (`Fiber::Stack`, also used by its overflow detector), so the
# distance from a local variable to the stack's low end is the headroom.
# 1 MiB is far more than one level of any template needs. The error is a
# `Crinja::RuntimeError`, classified as HWARO_E_TEMPLATE with the template
# location attached, like the include cap.
#
# Remove when: upstream bounds macro and `{% from %}` recursion.

require "crinja"

class Fiber
  # Bytes of stack left below the caller's frame on this fiber.
  def hwaro_stack_left : Int64
    marker = 0_u8
    pointerof(marker).address.to_i64 - @stack.pointer.address.to_i64
  end
end

module Hwaro::Ext::CrinjaRecursionDepth
  MIN_STACK_LEFT = 1_i64 << 20

  def self.check!(what : String) : Nil
    left = Fiber.current.hwaro_stack_left
    # Negative means the recorded bounds are not this stack's (Crystal notes
    # odd main-thread limits from the GC on some Linux systems): no guard
    # beats a false alarm on every macro call.
    return if left < 0 || left >= MIN_STACK_LEFT
    raise Crinja::RuntimeError.new(
      "Template recursion too deep in #{what} — " \
      "a macro without a base case, or a {% from %} import cycle?"
    )
  end
end

class Crinja::Tag::From < Crinja::Tag
  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    Hwaro::Ext::CrinjaRecursionDepth.check!("{% from %}")
    previous_def
  end
end

class Crinja::Tag::Macro::MacroFunction
  def call(arguments : Crinja::Arguments)
    Hwaro::Ext::CrinjaRecursionDepth.check!("macro `#{name}`")
    previous_def
  end
end
