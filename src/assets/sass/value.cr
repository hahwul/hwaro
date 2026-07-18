# Typed values for SassScript expression evaluation.
#
# Values exist only *during* expression evaluation — variables, mixin
# arguments, and module members are still stored as strings (verbatim CSS
# text) and coerced into typed values on demand (`Expr.coerce`). `Raw`
# carries any token soup the type system doesn't model (hex colors,
# `url(...)`, `calc(...)`, vendor junk), which is what keeps plain-CSS
# passthrough safe: an unmodeled value round-trips as its exact text.
#
# `SoftEvalError` signals "this expression isn't computable" (unit clash,
# comparing non-numbers, ...). Lenient contexts (declaration values)
# rescue it and fall back to verbatim text; strict contexts (@if
# conditions, function bodies) convert it to a located SyntaxError.

module Hwaro
  module Assets
    module Sass
      # Raised when an expression can't be evaluated. Never escapes the
      # compiler: lenient callers fall back to textual resolution, strict
      # callers convert to SyntaxError.
      class SoftEvalError < Exception
      end

      abstract class Value
        # CSS text for this value (what lands in output).
        abstract def to_css : String

        # Round-trippable text for this value — the spelling that
        # `Expr.coerce` can parse back into an equal value. This is what
        # variable storage and `meta.inspect` need, and it is NOT the same
        # as `to_css`: CSS output drops nulls from lists and never
        # parenthesizes a sublist, both of which destroy structure.
        # Mirrors dart-sass's `inspect` vs `toCssString` split.
        def inspect_css : String
          to_css
        end

        def truthy? : Bool
          true
        end

        # Sass equality (`==`). Subclasses override; default is identity
        # on serialized text.
        def eq?(other : Value) : Bool
          to_css == other.to_css
        end
      end

      class Number < Value
        getter value : Float64
        getter unit : String
        # Original source spelling (".5em"); kept so uncomputed numbers
        # serialize byte-identically.
        getter lexeme : String?

        def initialize(@value : Float64, @unit : String = "", @lexeme : String? = nil)
        end

        def to_css : String
          if lex = @lexeme
            lex
          else
            Number.format(@value) + @unit
          end
        end

        # dart-sass-style number formatting: integers without a decimal
        # point, floats rounded to 10 digits with trailing zeros trimmed.
        #
        # Never routes through `Float64#to_s`, which switches to exponent
        # form outside roughly [1e-4, 1e16). CSS has no exponent syntax and
        # no Infinity/NaN literals, so `3.33333e-5px` is not a number a
        # browser can read — it drops the whole declaration. Small values
        # are reachable from ordinary ratio math (opacity, scale).
        def self.format(value : Float64) : String
          unless value.finite?
            return "calc(NaN)" if value.nan?
            return value > 0 ? "calc(infinity)" : "calc(-infinity)"
          end
          rounded = value.round(10)
          rounded = 0.0 if rounded == 0 # avoid "-0"
          return rounded.to_i64.to_s if rounded == rounded.trunc && rounded.abs < 1e15

          s = sprintf("%.10f", rounded)
          s = s.rstrip('0').rstrip('.') if s.includes?('.')
          s
        end

        def eq?(other : Value) : Bool
          return false unless other.is_a?(Number)
          # Equality needs units to actually match — `1px == 1` is false.
          # `compatible_unit?` (one side unitless adopts the other's unit)
          # is the right rule for arithmetic and comparison, but using it
          # here silently picks the wrong `@if` branch and collides map
          # keys that differ only by unit.
          unit == other.unit && value == other.value
        end

        # v1 unit model: identical units or one side unitless. No
        # px↔cm-style conversions.
        def compatible_unit?(other : Number) : Bool
          unit.empty? || other.unit.empty? || unit == other.unit
        end

        def result_unit(other : Number) : String
          unit.empty? ? other.unit : unit
        end

        def int_value(context : String) : Int32
          unless value == value.trunc && value.abs < Int32::MAX
            raise SoftEvalError.new("#{context} must be an integer, got #{to_css}")
          end
          value.to_i
        end
      end

      class Str < Value
        # Raw text between the quotes, escapes preserved verbatim.
        getter text : String
        getter quoted : Bool
        getter quote_char : Char

        def initialize(@text : String, @quoted : Bool, @quote_char : Char = '"')
        end

        def to_css : String
          @quoted ? "#{@quote_char}#{@text}#{@quote_char}" : @text
        end

        def eq?(other : Value) : Bool
          # Quoted and unquoted strings with the same text are equal
          # (dart-sass semantics).
          other.is_a?(Str) && text == other.text
        end
      end

      class BoolV < Value
        getter value : Bool

        def initialize(@value : Bool)
        end

        def to_css : String
          @value ? "true" : "false"
        end

        def truthy? : Bool
          @value
        end

        def eq?(other : Value) : Bool
          other.is_a?(BoolV) && value == other.value
        end
      end

      class NullV < Value
        def to_css : String
          ""
        end

        # Null vanishes in CSS output but must survive storage as a value.
        def inspect_css : String
          "null"
        end

        def truthy? : Bool
          false
        end

        def eq?(other : Value) : Bool
          other.is_a?(NullV)
        end
      end

      class ListV < Value
        enum Sep
          Space
          Comma
          Slash
        end

        getter items : Array(Value)
        getter sep : Sep
        getter bracketed : Bool

        def initialize(@items : Array(Value), @sep : Sep = Sep::Space, @bracketed : Bool = false)
        end

        def to_css : String
          joiner =
            case @sep
            in Sep::Space then " "
            in Sep::Comma then ", "
            in Sep::Slash then " / "
            end
          inner = @items.map(&.to_css).reject(&.empty?).join(joiner)
          @bracketed ? "[#{inner}]" : inner
        end

        # Unlike `to_css`: keeps null members (they are real elements, so
        # dropping them changes `length`) and parenthesizes unbracketed
        # sublists so nesting survives a storage round-trip.
        def inspect_css : String
          return "()" if @items.empty?
          joiner =
            case @sep
            in Sep::Space then " "
            in Sep::Comma then ", "
            in Sep::Slash then " / "
            end
          inner = @items.map do |item|
            text = item.inspect_css
            item.is_a?(ListV) && !item.bracketed ? "(#{text})" : text
          end.join(joiner)
          @bracketed ? "[#{inner}]" : inner
        end

        def eq?(other : Value) : Bool
          return false unless other.is_a?(ListV)
          return false unless sep == other.sep && bracketed == other.bracketed
          return false unless items.size == other.items.size
          items.zip(other.items).all? { |a, b| a.eq?(b) }
        end
      end

      # Map entries avoid Tuple({Value, Value}) — tuples of abstract
      # class elements crash Crystal's codegen (virtual-type assign).
      record MapEntry, key : Value, value : Value

      class MapV < Value
        getter entries : Array(MapEntry)

        def initialize(@entries : Array(MapEntry))
        end

        def to_css : String
          "(" + @entries.map { |e| "#{e.key.to_css}: #{e.value.to_css}" }.join(", ") + ")"
        end

        # Entry values go through `inspect_css` so a comma list or nested
        # map stays parseable as one entry — with `to_css` the commas of a
        # nested list merge into the map's own separator and the text no
        # longer re-parses as a map.
        def inspect_css : String
          "(" + @entries.map do |e|
            value = e.value
            text = value.inspect_css
            text = "(#{text})" if value.is_a?(ListV) && !value.bracketed && value.sep == ListV::Sep::Comma
            "#{e.key.inspect_css}: #{text}"
          end.join(", ") + ")"
        end

        def []?(key : Value) : Value?
          @entries.each do |entry|
            return entry.value if entry.key.eq?(key)
          end
          nil
        end

        def eq?(other : Value) : Bool
          return false unless other.is_a?(MapV)
          return false unless entries.size == other.entries.size
          entries.all? do |entry|
            found = other[entry.key]?
            !found.nil? && entry.value.eq?(found)
          end
        end
      end

      # Unmodeled token soup: hex colors, url(...)/calc(...) spans,
      # reconstructed unknown-function calls. Serializes verbatim.
      class Raw < Value
        getter text : String

        def initialize(@text : String)
        end

        def to_css : String
          @text
        end
      end
    end
  end
end
