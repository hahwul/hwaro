# Jinja2 slice subscripts: `pages[:10]`, `items[1:]`, `title[0:20]`,
# `pages[::-1]`.
#
# Upstream Crinja only parses `x[expr]`; a `:` inside the brackets was a
# syntax error, so the one cheap way to take the first N items of a list was
# missing. The alternatives all cost a full pass over the list per render:
# `{% if loop.index <= 10 %}` still iterates everything, `slice` is Jinja's
# split-into-N-groups filter, and `batch(10) | first` builds every batch.
# Zola's templates write the same thing as `pages | slice(end=10)` or
# `pages[:10]` (issue #883).
#
# Semantics are Python's, as in Jinja2: start/stop/step may each be omitted
# or none, negative indices count from the end, out-of-range bounds clamp,
# a zero step raises. Lists slice to a new list, strings to a string by
# character (a safe string stays safe). Anything else raises a TypeError, as
# it does in Jinja2. Only `[a:b]` forms are new — `x[expr]` parses exactly as
# before.

module Crinja::AST
  expression_node SliceExpression,
    identifier : ExpressionNode,
    start : ExpressionNode?,
    stop : ExpressionNode?,
    step : ExpressionNode?
end

class Crinja::Parser::ExpressionParser
  # Upstream body, with the LEFT_BRACKET branch going through
  # `parse_subscript` (Jinja2's `parse_subscribed`).
  private def parse_variable_expression
    identifier = parse_literal
    identifier.location_end = current_token.location

    loop do
      case current_token.kind
      when Kind::LEFT_PAREN
        next_token
        identifier = parse_call_expression(identifier)
      when Kind::LEFT_BRACKET
        next_token
        identifier = parse_subscript(identifier)
      when Kind::POINT
        next_token
        member = AST::Empty.new

        if current_token.kind == Kind::IDENTIFIER || current_token.kind == Kind::INTEGER
          member = AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
          member.location_end = next_token.location
        else
          unexpected_token Kind::IDENTIFIER
        end

        if member.is_a? AST::IdentifierLiteral
          identifier = AST::MemberExpression.new(identifier, member).at(identifier, member)
        end
      else
        return identifier
      end
    end
  end

  # Called with the opening `[` consumed. `:` lexes as DICT_ASSIGN.
  private def parse_subscript(identifier : AST::ExpressionNode) : AST::ExpressionNode
    start = current_token.kind == Kind::DICT_ASSIGN ? nil : parse_expression

    unless current_token.kind == Kind::DICT_ASSIGN
      end_location = current_token.location
      expect Kind::RIGHT_BRACKET
      return AST::IndexExpression.new(identifier, start.as(AST::ExpressionNode)).at(identifier.location_start, end_location)
    end

    next_token
    stop = slice_bound? ? parse_expression : nil

    step = nil
    if current_token.kind == Kind::DICT_ASSIGN
      next_token
      step = parse_expression if slice_bound?
    end

    end_location = current_token.location
    expect Kind::RIGHT_BRACKET
    AST::SliceExpression.new(identifier, start, stop, step).at(identifier.location_start, end_location)
  end

  private def slice_bound? : Bool
    current_token.kind != Kind::DICT_ASSIGN && current_token.kind != Kind::RIGHT_BRACKET
  end
end

class Crinja::Evaluator
  def evaluate(expression : AST::SliceExpression)
    object = value! expression.identifier
    start = slice_index(expression.start)
    stop = slice_index(expression.stop)
    step = slice_index(expression.step) || 1_i64
    raise TypeError.new("slice step cannot be zero") if step == 0

    case raw = object.raw
    when Array(Value)
      @env.__slice_of(raw, start, stop, step)
    when String
      Crinja.slice_string(raw, start, stop, step)
    when SafeString
      SafeString.new(Crinja.slice_string(raw.to_s, start, stop, step))
    else
      raise TypeError.new(object, "#{raw.class} cannot be sliced")
    end
  rescue ex : Crinja::Error
    ex.at(expression) unless ex.has_location?
    raise ex
  end

  private def slice_index(expression : AST::ExpressionNode?) : Int64?
    return if expression.nil?

    index = value(expression)
    return if index.none? || index.undefined?

    raw = index.raw
    raise TypeError.new(index, "slice indices must be integers or none") unless raw.is_a?(Int)
    raw.to_i64
  end
end

class Crinja
  # Slices of one list, memoized per environment: the same `pages[:10]` on
  # every page returns the SAME array, so a loop over it hits the for-loop
  # fragment cache (keyed by collection identity, crinja_render_perf.cr)
  # instead of filling it with one dead entry per page. Sound for the same
  # reason that cache is: a list's contents never change under a fixed
  # identity during a render pass (templates cannot mutate lists, and hwaro
  # builds its collections once per build). Entries pin their source list so
  # its object_id cannot be recycled into a false hit; past the cap, slices
  # are simply built fresh.
  SLICE_MEMO_MAX = 256

  record SliceEntry, source : Array(Value), result : Array(Value)

  getter __slice_memo : Hash(::Tuple(UInt64, Int64?, Int64?, Int64), SliceEntry) do
    Hash(::Tuple(UInt64, Int64?, Int64?, Int64), SliceEntry).new
  end

  def __slice_of(source : Array(Value), start : Int64?, stop : Int64?, step : Int64) : Array(Value)
    key = {source.object_id, start, stop, step}
    if entry = __slice_memo[key]?
      return entry.result
    end

    result = if step == 1
               first, count = Crinja.contiguous_slice(source.size, start, stop)
               source[first, count]
             else
               items = [] of Value
               Crinja.each_slice_index(source.size, start, stop, step) { |i| items << source[i] }
               items
             end
    __slice_memo[key] = SliceEntry.new(source, result) if __slice_memo.size < SLICE_MEMO_MAX
    result
  end

  # Python's slice index walk (PySlice_AdjustIndices): yields each selected
  # index of a sequence of `size` items, in order.
  def self.each_slice_index(size : Int, start : Int64?, stop : Int64?, step : Int64, &) : Nil
    size = size.to_i64
    if step > 0
      first = start.nil? ? 0_i64 : clamp_slice_bound(start, size, step)
      last = stop.nil? ? size : clamp_slice_bound(stop, size, step)
      i = first
      while i < last
        yield i
        # `last - i` cannot overflow; `i + step` can, for a huge step.
        break if step >= last - i
        i += step
      end
    else
      first = start.nil? ? size - 1 : clamp_slice_bound(start, size, step)
      last = stop.nil? ? -1_i64 : clamp_slice_bound(stop, size, step)
      i = first
      while i > last
        yield i
        break if step <= last - i
        i += step
      end
    end
  end

  private def self.clamp_slice_bound(bound : Int64, size : Int64, step : Int64) : Int64
    if bound < 0
      bound += size
      bound < 0 ? (step < 0 ? -1_i64 : 0_i64) : bound
    elsif bound >= size
      step < 0 ? size - 1 : size
    else
      bound
    end
  end

  # First index and length of a step-1 slice.
  def self.contiguous_slice(size : Int, start : Int64?, stop : Int64?) : ::Tuple(Int64, Int64)
    size = size.to_i64
    first = start.nil? ? 0_i64 : clamp_slice_bound(start, size, 1_i64)
    last = stop.nil? ? size : clamp_slice_bound(stop, size, 1_i64)
    {first, Math.max(last - first, 0_i64)}
  end

  def self.slice_string(string : String, start : Int64?, stop : Int64?, step : Int64) : String
    if step == 1
      first, count = contiguous_slice(string.size, start, stop)
      return string[first, count]
    end

    chars = string.chars
    String.build do |io|
      each_slice_index(chars.size, start, stop, step) { |i| io << chars[i] }
    end
  end
end
