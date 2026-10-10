# Jinja2's `loop` variable, completed.
#
# * `loop.previtem`, `loop.nextitem`, `loop.depth`, `loop.depth0` printed
#   nothing and `loop.changed(…)` raised: upstream never defined them for a
#   plain (non-recursive) loop.
# * A filtered loop (`{% for p in pages if p.extra.featured %}`) iterates a
#   lazy iterator of unknown size, and `loop.length`, `loop.revindex` and
#   `loop.revindex0` printed -2147483648 (the "unknown" sentinel) on every
#   item but the last. They now count the remaining items on first use,
#   as Jinja2 does.
# * The `if` condition of a filtered loop was evaluated with the item
#   variables written into the enclosing scope, so after the loop `{{ p }}`
#   still held the last item tested. It now runs in a scope of its own.
#   (That also keeps the length count above from clobbering the current
#   item while the body runs.)
class Crinja::Tag::For::ForLoop
  @previtem : Value? = nil
  @nextitem : Value? = nil
  @changed_last : Array(Value)? = nil

  def crinja_attribute(attr : Value) : Value
    case attr.to_string
    when "previtem"
      @previtem || Value.new(Crinja::Undefined.new("previtem"))
    when "nextitem"
      @nextitem || Value.new(Crinja::Undefined.new("nextitem"))
    when "changed"
      Value.new(ChangedMethod.new(self))
    when "depth"
      Value.new(1)
    when "depth0"
      Value.new(0)
    else
      previous_def
    end
  end

  def length
    count_remaining if @length == Int32::MIN
    @length
  end

  def revindex0
    count_remaining if @length == Int32::MIN
    @revindex0
  end

  def revindex
    revindex0 + 1
  end

  def each(&)
    value = iterator.next

    until value.is_a?(Iterator::Stop)
      @index0 += 1
      @revindex0 -= 1 unless @length == Int32::MIN

      next_value = iterator.next
      if next_value.is_a?(Iterator::Stop)
        @nextitem = nil
        @last = true
        @length = index
        @revindex0 = 0
      else
        @nextitem = next_value.as(Value)
      end

      yield value.as(Value)

      @previtem = value.as(Value)
      value = next_value
      @first = false
    end
  end

  # `loop.changed(*values)`: true when the values differ from the previous
  # call's (and on the first call).
  def __changed?(values : Array(Value)) : Bool
    changed = @changed_last != values
    @changed_last = values
    changed
  end

  # Size is unknown only for a lazy (filtered) iterator: drain what is left
  # into a buffer the loop keeps iterating from.
  private def count_remaining
    rest = [] of Value
    while !(item = @iterator.next).is_a?(Iterator::Stop)
      rest << item.as(Value)
    end
    @iterator = rest.each
    @length = index + (@nextitem ? 1 : 0) + rest.size
    @revindex0 = @length - index
  end

  class ChangedMethod
    include Callable

    def initialize(@loop : ForLoop)
    end

    def call(arguments : Arguments) : Value
      Value.new(@loop.__changed?(arguments.varargs.dup))
    end
  end
end

class Crinja::Tag::For::ConditionalIterator
  @scope : Context

  def initialize(@iterator : Iterator(Value), @condition : AST::ExpressionNode, @env : Crinja, @item_vars : Array(String))
    @scope = Context.new(@env.context)
  end

  def next
    loop do
      value = wrapped_next.as(Value)
      keep = @env.with_scope(@scope) do |context|
        context[LOOP_VARIABLE] = StrictUndefined.new(LOOP_VARIABLE)
        context.unpack(@item_vars, value)
        @env.evaluator.value(@condition).truthy?
      end
      return value if keep
    end
  end
end
