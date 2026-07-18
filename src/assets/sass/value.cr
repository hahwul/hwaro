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
        # CSS text for this value (what lands in output / string storage).
        abstract def to_css : String

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
        def self.format(value : Float64) : String
          rounded = value.round(10)
          rounded = 0.0 if rounded == 0 # avoid "-0"
          if rounded == rounded.trunc && rounded.abs < 1e15
            rounded.to_i64.to_s
          else
            s = rounded.to_s
            s
          end
        end

        def eq?(other : Value) : Bool
          return false unless other.is_a?(Number)
          return false unless compatible_unit?(other)
          value == other.value
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
