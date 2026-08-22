# Built-in Sass functions: the `sass:math` / `sass:string` / `sass:list`
# / `sass:map` / `sass:meta` module subset plus their dart-sass legacy
# global names.
#
# Deliberately excluded:
# - `math.random` / `unique-id()` — builds must be deterministic.
# - Global `min()`/`max()`/`round()`/`abs()`/`clamp()` shadow real CSS
#   functions; when their arguments aren't statically computable (vw/px
#   mixes, `min(100% - 10px, 2rem)`) they raise SoftEvalError and the
#   lenient value path passes the call through as CSS — same behavior
#   dart-sass implements with special cases.
# - `rgb()`/`rgba()`/`hsl()`/`hsla()` are NOT evaluated in their CSS
#   forms. dart-sass folds `rgb(0, 0, 0)` to `black`, but the plain-CSS
#   guarantee here outranks that: rewriting a literal every stylesheet
#   already contains would change output for existing sites. Only the
#   Sass-only two-argument `rgba($color, $alpha)` / `rgb($color, $alpha)`
#   spelling — which is not valid CSS and currently emits broken output —
#   evaluates; every other shape raises SoftEvalError and passes through.
# - `grayscale()`, `invert()`, `saturate()` and `opacity()` are also CSS
#   filter functions. They evaluate only when handed a color; a numeric
#   argument (`filter: grayscale(50%)`) raises SoftEvalError and stays
#   verbatim, the same shadowing rule `min()`/`max()` follow.
#
# All argument mismatches raise SoftEvalError: lenient contexts fall back
# to verbatim CSS, strict contexts surface a located error.

require "./value"
require "./color"
require "./expr"
require "./extend"
require "./parser"

module Hwaro
  module Assets
    module Sass
      module Builtins
        alias Fn = Proc(Array(Value), Hash(String, Value), Value)

        # ---------------------------------------------------------------
        # Argument helpers
        # ---------------------------------------------------------------

        private def self.ascii_upcase(text : String) : String
          text.gsub { |c| c.ascii_lowercase? ? c.upcase : c }
        end

        private def self.ascii_downcase(text : String) : String
          text.gsub { |c| c.ascii_uppercase? ? c.downcase : c }
        end

        private def self.no_kwargs!(name : String, kwargs : Hash(String, Value)) : Nil
          return if kwargs.empty?
          raise SoftEvalError.new("#{name}() does not support keyword arguments")
        end

        # Rebinds keyword arguments onto their positional slots so the
        # builtin bodies keep reading `args` positionally —
        # `list.append($l, x, $separator: comma)` reaches the same slots
        # as `list.append($l, x, comma)`. Trailing unfilled optionals drop
        # off; a hole before a filled slot (`slice($s, $end-at: 3)` with
        # no $start-at) is a missing required argument.
        private def self.args_with_kwargs(name : String, args : Array(Value),
                                          kwargs : Hash(String, Value),
                                          params : Array(String),
                                          defaults : Hash(Int32, Value)? = nil) : Array(Value)
          return args if kwargs.empty?
          bound = bind_args(name, args, kwargs, params)
          while !bound.empty? && bound.last.nil?
            bound.pop
          end
          bound.map_with_index do |value, index|
            value || defaults.try(&.[index]?) ||
              raise SoftEvalError.new("#{name}() is missing required argument $#{params[index]}")
          end
        end

        private def self.arity!(name : String, args : Array(Value), min : Int32, max : Int32 = min) : Nil
          return if args.size >= min && args.size <= max
          expected = min == max ? min.to_s : "#{min}..#{max}"
          raise SoftEvalError.new("#{name}() expects #{expected} argument(s), got #{args.size}")
        end

        private def self.number!(name : String, value : Value) : Number
          case value
          when Number
            value
          when Raw, Str
            text = value.is_a?(Raw) ? value.text : value.as(Str).text
            coerced = Expr.coerce(text)
            return coerced if coerced.is_a?(Number)
            if coerced.is_a?(ListV) && (n = Expr.slash_division?(coerced))
              return n
            end
            raise SoftEvalError.new("#{name}() expects a number, got #{value.to_css.inspect}")
          when ListV
            # An undivided slash pair (`min(10 / 2, 8)`) is a lazy
            # division in dart-sass; a numeric context folds it.
            Expr.slash_division?(value) ||
              raise SoftEvalError.new("#{name}() expects a number, got #{value.to_css.inspect}")
          else
            raise SoftEvalError.new("#{name}() expects a number, got #{value.to_css.inspect}")
          end
        end

        private def self.string!(name : String, value : Value) : Str
          case value
          when Str
            value
          when Raw
            Str.new(value.text, quoted: false)
          else
            raise SoftEvalError.new("#{name}() expects a string, got #{value.to_css.inspect}")
          end
        end

        # Scalars act as single-element lists (Sass semantics).
        private def self.list_of(value : Value) : Array(Value)
          case value
          when ListV
            value.items
          when MapV
            value.entries.map { |e| ListV.new([e.key, e.value], ListV::Sep::Space).as(Value) }
          else
            [value]
          end
        end

        private def self.map!(name : String, value : Value) : MapV
          case value
          when MapV
            value
          when ListV
            return MapV.new([] of MapEntry) if value.items.empty?
            raise SoftEvalError.new("#{name}() expects a map, got #{value.to_css.inspect}")
          when Raw
            coerced = Expr.coerce(value.text)
            return coerced if coerced.is_a?(MapV)
            return MapV.new([] of MapEntry) if coerced.is_a?(ListV) && coerced.items.empty?
            raise SoftEvalError.new("#{name}() expects a map, got #{value.to_css.inspect}")
          else
            raise SoftEvalError.new("#{name}() expects a map, got #{value.to_css.inspect}")
          end
        end

        # A color argument. `Raw` is the shape a source color arrives in
        # (`#336699` lexes as token soup), so parsing happens here on
        # demand rather than in the lexer — that is what keeps untouched
        # colors byte-identical. Quoted strings are never colors:
        # `"red"` is a string in Sass, only bare `red` is a color.
        private def self.color?(value : Value) : ColorV?
          case value
          when ColorV then value
          when Raw    then ColorV.parse?(value.text)
          when Str    then value.quoted ? nil : ColorV.parse?(value.text)
          end
        end

        private def self.color!(name : String, value : Value) : ColorV
          color?(value) ||
            raise SoftEvalError.new("#{name}() expects a color, got #{value.to_css.inspect}")
        end

        # Colour argument for a built-in whose name is also a real CSS
        # function. Declining with ShapeMismatch (rather than raising
        # SoftEvalError) is what keeps `filter: grayscale(50%)` from
        # unwinding every other expression in its declaration.
        private def self.shadowed_color!(value : Value) : ColorV
          color?(value) || raise ShapeMismatch.new
        end

        private def self.shadowed_arity!(args : Array(Value), min : Int32, max : Int32 = min) : Nil
          raise ShapeMismatch.new unless args.size >= min && args.size <= max
        end

        # Binds a shadowed built-in's arguments, declining rather than
        # erroring when a required one is absent. `saturate(180%)` is the CSS
        # filter: it must reconstruct verbatim, not raise, or it takes every
        # other expression in the declaration down with it.
        private def self.shadowed_bind!(name : String, args : Array(Value),
                                        kwargs : Hash(String, Value),
                                        params : Array(String), required : Int32) : Array(Value?)
          shadowed_arity!(args, 0, params.size)
          bound = bind_args(name, args, kwargs, params)
          required.times { |index| raise ShapeMismatch.new unless bound[index] }
          bound
        end

        # Rejects NaN/Infinity before it reaches channel math. `NaN.to_i`
        # raises OverflowError, which nothing in the compiler catches, so an
        # unguarded NaN escapes as a bare arithmetic crash with no source
        # location instead of the normal located error.
        private def self.finite!(name : String, number : Number) : Float64
          value = number.value
          unless value.finite?
            raise SoftEvalError.new("#{name}() expects a finite number, got #{number.to_css}")
          end
          value
        end

        # Percentage-style amount (`10%` or bare `10`). Out-of-range values
        # raise rather than clamp: silently turning `lighten($c, -10%)` into
        # a no-op, or `darken($c, 200%)` into black, hides the mistake in
        # output that looks perfectly valid. dart-sass errors here too.
        private def self.amount!(name : String, value : Value,
                                 min : Float64 = 0.0, max : Float64 = 100.0) : Float64
          raw = finite!(name, number!(name, value))
          unless raw >= min && raw <= max
            raise SoftEvalError.new(
              "#{name}(): expected #{Number.format(raw)} to be within #{Number.format(min)} and #{Number.format(max)}")
          end
          raw
        end

        # Alpha-style amount, on 0..1. A percentage spelling (`50%`) is
        # accepted and scaled, matching dart-sass.
        private def self.alpha!(name : String, value : Value,
                                min : Float64 = 0.0, max : Float64 = 1.0) : Float64
          number = number!(name, value)
          raw = finite!(name, number)
          raw /= 100.0 if number.unit == "%"
          unless raw >= min && raw <= max
            raise SoftEvalError.new(
              "#{name}(): expected #{Number.format(raw)} to be within #{Number.format(min)} and #{Number.format(max)}")
          end
          raw
        end

        # Rejects keyword arguments the function doesn't define, so a typo
        # (`$lightnes:`) fails loudly instead of being silently dropped.
        # Keys arrive already normalized to the `-` spelling (`eval_call`
        # runs them through `Sass.normalize_ident`), so no further
        # translation is needed here.
        private def self.known_kwargs!(name : String, kwargs : Hash(String, Value),
                                       allowed : Array(String)) : Nil
          kwargs.each_key do |key|
            next if allowed.includes?(key)
            raise SoftEvalError.new("#{name}() has no argument named $#{key}")
          end
        end

        # Binds positional arguments and the keyword spellings dart-sass
        # accepts onto `params`, so `darken($c, $amount: 10%)` reaches the
        # same slots as `darken($c, 10%)`. Returns one entry per parameter,
        # nil where the caller supplied nothing.
        private def self.bind_args(name : String, args : Array(Value),
                                   kwargs : Hash(String, Value),
                                   params : Array(String)) : Array(Value?)
          known_kwargs!(name, kwargs, params)
          if args.size > params.size
            raise SoftEvalError.new("#{name}() expects at most #{params.size} argument(s), got #{args.size}")
          end
          params.map_with_index do |param, index|
            positional = args[index]?
            if named = kwargs[param]?
              if positional
                raise SoftEvalError.new("#{name}() got multiple values for $#{param}")
              end
              next named.as(Value?)
            end
            positional.as(Value?)
          end
        end

        # `bind_args` plus a required-argument check on the leading
        # `required` parameters.
        private def self.bind!(name : String, args : Array(Value),
                               kwargs : Hash(String, Value),
                               params : Array(String), required : Int32) : Array(Value?)
          bound = bind_args(name, args, kwargs, params)
          required.times do |index|
            unless bound[index]
              raise SoftEvalError.new("#{name}() is missing required argument $#{params[index]}")
            end
          end
          bound
        end

        # Checks every argument is unit-compatible (identical, unitless, or
        # convertible) and returns the first non-empty unit — the basis the
        # min/max/clamp comparisons convert into.
        private def self.same_units!(name : String, numbers : Array(Number)) : String
          unit = ""
          numbers.each do |n|
            next if n.unit.empty?
            if unit.empty?
              unit = n.unit
            elsif unit != n.unit && Number.conversion_factor(n.unit, unit).nil?
              raise SoftEvalError.new("#{name}(): incompatible units #{unit} and #{n.unit}")
            end
          end
          unit
        end

        # A number's value expressed in `unit` for comparison purposes
        # (unitless operands compare as-is — dart-sass semantics).
        private def self.comparable_value(n : Number, unit : String) : Float64
          return n.value if unit.empty? || n.unit.empty? || n.unit == unit
          n.value * (Number.conversion_factor(n.unit, unit) || 1.0)
        end

        # An angle argument in degrees: bare numbers are radians for the
        # trig functions? No — dart-sass treats a unitless angle as
        # RADIANS for sin/cos/tan. Convertible angle units convert.
        private def self.radians!(name : String, n : Number) : Float64
          return n.value if n.unit.empty?
          factor = Number.conversion_factor(n.unit, "rad")
          raise SoftEvalError.new("#{name}() expects an angle, got #{n.to_css}") unless factor
          n.value * factor
        end

        private def self.unitless!(name : String, value : Value) : Float64
          n = number!(name, value)
          unless n.unit.empty?
            raise SoftEvalError.new("#{name}() expects a unitless number, got #{n.to_css}")
          end
          n.value
        end

        # ---------------------------------------------------------------
        # sass:math
        # ---------------------------------------------------------------

        MATH_FNS = {
          "div" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.div", args, kwargs, %w[number1 number2])
            arity!("math.div", args, 2)
            a = number!("math.div", args[0])
            b = number!("math.div", args[1])
            raise SoftEvalError.new("math.div(): division by zero") if b.value == 0
            value, unit = Expr.divide_numbers(a, b)
            Number.new(value, unit)
          end,
          "percentage" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.percentage", args, kwargs, %w[number])
            arity!("math.percentage", args, 1)
            n = number!("math.percentage", args[0])
            unless n.unit.empty?
              raise SoftEvalError.new("math.percentage() expects a unitless number, got #{n.to_css}")
            end
            Number.new(n.value * 100, "%")
          end,
          "round" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.round", args, kwargs, %w[number])
            arity!("round", args, 1)
            n = number!("round", args[0])
            # Sass rounds halves away from zero; Crystal's default is
            # banker's rounding, which sends round(2.5) to 2.
            Number.new(n.value.round(mode: :ties_away).to_f, n.unit)
          end,
          "ceil" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.ceil", args, kwargs, %w[number])
            arity!("ceil", args, 1)
            n = number!("ceil", args[0])
            Number.new(n.value.ceil.to_f, n.unit)
          end,
          "floor" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.floor", args, kwargs, %w[number])
            arity!("floor", args, 1)
            n = number!("floor", args[0])
            Number.new(n.value.floor.to_f, n.unit)
          end,
          "abs" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.abs", args, kwargs, %w[number])
            arity!("abs", args, 1)
            n = number!("abs", args[0])
            Number.new(n.value.abs, n.unit)
          end,
          "min" => Fn.new do |args, kwargs|
            no_kwargs!("math.min", kwargs)
            arity!("min", args, 1, Int32::MAX)
            numbers = args.map { |a| number!("min", a) }
            base = same_units!("min", numbers)
            # Return the winning operand as-is. Stamping the first non-empty
            # unit seen across all args onto the winner fabricates a unit
            # the result never had: `min(1, 2px)` is `1`, not `1px`.
            # Convertible units compare in a common basis (`min(1in, 50px)`
            # is `50px`).
            winner = numbers.min_by { |n| comparable_value(n, base) }
            Number.new(winner.value, winner.unit)
          end,
          "max" => Fn.new do |args, kwargs|
            no_kwargs!("math.max", kwargs)
            arity!("max", args, 1, Int32::MAX)
            numbers = args.map { |a| number!("max", a) }
            base = same_units!("max", numbers)
            winner = numbers.max_by { |n| comparable_value(n, base) }
            Number.new(winner.value, winner.unit)
          end,
          "clamp" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.clamp", args, kwargs, %w[min number max])
            arity!("math.clamp", args, 3)
            numbers = args.map { |a| number!("math.clamp", a) }
            base = same_units!("math.clamp", numbers)
            # As with min/max, the result is whichever operand wins, unit
            # included — not the value re-stamped with a scanned unit.
            low, mid, high = numbers[0], numbers[1], numbers[2]
            lv = comparable_value(low, base)
            mv = comparable_value(mid, base)
            hv = comparable_value(high, base)
            winner = mv < lv ? low : (mv > hv ? high : mid)
            Number.new(winner.value, winner.unit)
          end,
          "log" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.log", args, kwargs, %w[number base])
            arity!("math.log", args, 1, 2)
            value = unitless!("math.log", args[0])
            raise SoftEvalError.new("math.log() of a non-positive number") if value <= 0
            result = Math.log(value)
            if base_arg = args[1]?
              base = unitless!("math.log", base_arg)
              raise SoftEvalError.new("math.log(): invalid base #{Number.format(base)}") if base <= 0 || base == 1
              result /= Math.log(base)
            end
            Number.new(result, "")
          end,
          "hypot" => Fn.new do |args, kwargs|
            no_kwargs!("math.hypot", kwargs)
            arity!("math.hypot", args, 1, Int32::MAX)
            numbers = args.map { |a| number!("math.hypot", a) }
            unit = numbers[0].unit
            sum = numbers.reduce(0.0) do |acc, n|
              v =
                if unit.empty? || n.unit.empty? || n.unit == unit
                  raise SoftEvalError.new("math.hypot(): mixed unit and unitless arguments") if unit.empty? != n.unit.empty?
                  n.value
                else
                  factor = Number.conversion_factor(n.unit, unit)
                  raise SoftEvalError.new("math.hypot(): incompatible units #{unit} and #{n.unit}") unless factor
                  n.value * factor
                end
              acc + v * v
            end
            Number.new(Math.sqrt(sum), unit)
          end,
          "sin" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.sin", args, kwargs, %w[number])
            arity!("math.sin", args, 1)
            Number.new(Math.sin(radians!("math.sin", number!("math.sin", args[0]))), "")
          end,
          "cos" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.cos", args, kwargs, %w[number])
            arity!("math.cos", args, 1)
            Number.new(Math.cos(radians!("math.cos", number!("math.cos", args[0]))), "")
          end,
          "tan" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.tan", args, kwargs, %w[number])
            arity!("math.tan", args, 1)
            Number.new(Math.tan(radians!("math.tan", number!("math.tan", args[0]))), "")
          end,
          "asin" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.asin", args, kwargs, %w[number])
            arity!("math.asin", args, 1)
            v = unitless!("math.asin", args[0])
            raise SoftEvalError.new("math.asin() argument must be within -1 and 1") if v < -1 || v > 1
            Number.new(Math.asin(v) * 180.0 / Math::PI, "deg")
          end,
          "acos" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.acos", args, kwargs, %w[number])
            arity!("math.acos", args, 1)
            v = unitless!("math.acos", args[0])
            raise SoftEvalError.new("math.acos() argument must be within -1 and 1") if v < -1 || v > 1
            Number.new(Math.acos(v) * 180.0 / Math::PI, "deg")
          end,
          "atan" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.atan", args, kwargs, %w[number])
            arity!("math.atan", args, 1)
            Number.new(Math.atan(unitless!("math.atan", args[0])) * 180.0 / Math::PI, "deg")
          end,
          "atan2" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.atan2", args, kwargs, %w[y x])
            arity!("math.atan2", args, 2)
            y = number!("math.atan2", args[0])
            x = number!("math.atan2", args[1])
            unless y.compatible_unit?(x)
              raise SoftEvalError.new("math.atan2(): incompatible units #{y.unit} and #{x.unit}")
            end
            xv = y.unit.empty? ? x.value : y.coerce_value(x)
            Number.new(Math.atan2(y.value, xv) * 180.0 / Math::PI, "deg")
          end,
          "pow" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.pow", args, kwargs, %w[base exponent])
            arity!("math.pow", args, 2)
            base = number!("math.pow", args[0])
            exp = number!("math.pow", args[1])
            unless base.unit.empty? && exp.unit.empty?
              raise SoftEvalError.new("math.pow() expects unitless numbers")
            end
            Number.new(base.value ** exp.value, "")
          end,
          "sqrt" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.sqrt", args, kwargs, %w[number])
            arity!("math.sqrt", args, 1)
            n = number!("math.sqrt", args[0])
            unless n.unit.empty?
              raise SoftEvalError.new("math.sqrt() expects a unitless number")
            end
            raise SoftEvalError.new("math.sqrt() of a negative number") if n.value < 0
            Number.new(Math.sqrt(n.value), "")
          end,
          "unit" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.unit", args, kwargs, %w[number])
            arity!("unit", args, 1)
            Str.new(number!("unit", args[0]).unit, quoted: true)
          end,
          "is-unitless" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.is-unitless", args, kwargs, %w[number])
            arity!("unitless", args, 1)
            BoolV.new(number!("unitless", args[0]).unit.empty?)
          end,
          "compatible" => Fn.new do |args, kwargs|
            args = args_with_kwargs("math.compatible", args, kwargs, %w[number1 number2])
            arity!("comparable", args, 2)
            a = number!("comparable", args[0])
            b = number!("comparable", args[1])
            BoolV.new(a.compatible_unit?(b))
          end,
        }

        MATH_VARS = {
          "pi" => "3.1415926536",
          "e"  => "2.7182818285",
          # Storage is text, so the constants are stored as spellings that
          # parse back to the right Float64. dart-sass prints $epsilon as
          # 0 (10-digit rounding) but compares it > 0 — the scientific
          # spelling keeps the comparison correct and short (a verbatim
          # emission is invalid CSS either way). $max-number uses dart's
          # zero-padded shortest-representation digits, which is also what
          # Number.format prints for computed values of this magnitude.
          "epsilon"          => "2.220446049250313e-16",
          "max-safe-integer" => "9007199254740991",
          "min-safe-integer" => "-9007199254740991",
          "max-number"       => "17976931348623157" + "0" * 292,
          "min-number"       => "5e-324",
        }

        # ---------------------------------------------------------------
        # sass:string
        # ---------------------------------------------------------------

        STRING_FNS = {
          "quote" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.quote", args, kwargs, %w[string])
            arity!("quote", args, 1)
            s = string!("quote", args[0])
            Str.new(s.text, quoted: true)
          end,
          "unquote" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.unquote", args, kwargs, %w[string])
            arity!("unquote", args, 1)
            s = string!("unquote", args[0])
            Str.new(s.text, quoted: false)
          end,
          "length" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.length", args, kwargs, %w[string])
            arity!("str-length", args, 1)
            Number.new(string!("str-length", args[0]).text.size.to_f, "")
          end,
          "index" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.index", args, kwargs, %w[string substring])
            arity!("str-index", args, 2)
            haystack = string!("str-index", args[0]).text
            needle = string!("str-index", args[1]).text
            idx = haystack.index(needle)
            idx ? Number.new((idx + 1).to_f, "") : NullV.new
          end,
          "slice" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.slice", args, kwargs, %w[string start-at end-at])
            arity!("str-slice", args, 2, 3)
            text = string!("str-slice", args[0]).text
            quoted = string!("str-slice", args[0]).quoted
            start_at = number!("str-slice", args[1]).int_value("str-slice() start")
            end_at = args[2]? ? number!("str-slice", args[2]).int_value("str-slice() end") : -1
            size = text.size
            from = start_at < 0 ? Math.max(size + start_at, 0) : Math.max(start_at - 1, 0)
            to = end_at < 0 ? size + end_at : Math.min(end_at - 1, size - 1)
            sliced = from > to ? "" : text[from..to]
            Str.new(sliced, quoted: quoted)
          end,
          "insert" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.insert", args, kwargs, %w[string insert index])
            arity!("str-insert", args, 3)
            base = string!("str-insert", args[0])
            insert = string!("str-insert", args[1]).text
            index = number!("str-insert", args[2]).int_value("str-insert() index")
            size = base.text.size
            # 1-based; negative counts from the end where -1 inserts AT the
            # end (dart-sass: `insert("abc", "X", -1)` is `"abcX"`).
            index = size + index + 2 if index < 0
            offset = (index - 1).clamp(0, size)
            Str.new(base.text[0, offset] + insert + base.text[offset..],
              quoted: base.quoted, quote_char: base.quote_char)
          end,
          "split" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.split", args, kwargs, %w[string separator limit])
            arity!("string.split", args, 2, 3)
            text = string!("string.split", args[0]).text
            sep = string!("string.split", args[1]).text
            limit =
              if (arg = args[2]?) && !arg.is_a?(NullV)
                number!("string.split", arg).int_value("string.split() limit")
              end
            parts =
              if sep.empty?
                text.chars.map(&.to_s)
              elsif limit
                text.split(sep, limit + 1)
              else
                text.split(sep)
              end
            ListV.new(parts.map { |p| Str.new(p, quoted: true).as(Value) },
              ListV::Sep::Comma, bracketed: true)
          end,
          "to-upper-case" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.to-upper-case", args, kwargs, %w[string])
            arity!("to-upper-case", args, 1)
            s = string!("to-upper-case", args[0])
            # Sass maps ASCII only; Crystal's `upcase` is Unicode-aware.
            Str.new(ascii_upcase(s.text), quoted: s.quoted, quote_char: s.quote_char)
          end,
          "to-lower-case" => Fn.new do |args, kwargs|
            args = args_with_kwargs("string.to-lower-case", args, kwargs, %w[string])
            arity!("to-lower-case", args, 1)
            s = string!("to-lower-case", args[0])
            Str.new(ascii_downcase(s.text), quoted: s.quoted, quote_char: s.quote_char)
          end,
        }

        # ---------------------------------------------------------------
        # sass:list
        # ---------------------------------------------------------------

        private def self.sep_from(value : Value?, current : ListV::Sep) : ListV::Sep
          return current unless value
          name = value.is_a?(Str) ? value.text : value.to_css
          case name
          when "comma" then ListV::Sep::Comma
          when "space" then ListV::Sep::Space
          when "slash" then ListV::Sep::Slash
          when "auto"  then current
          else
            raise SoftEvalError.new("invalid list separator #{name.inspect}")
          end
        end

        LIST_FNS = {
          "length" => Fn.new do |args, kwargs|
            args = args_with_kwargs("list.length", args, kwargs, %w[list])
            arity!("length", args, 1)
            Number.new(list_of(args[0]).size.to_f, "")
          end,
          "nth" => Fn.new do |args, kwargs|
            args = args_with_kwargs("list.nth", args, kwargs, %w[list n])
            arity!("nth", args, 2)
            items = list_of(args[0])
            n = number!("nth", args[1]).int_value("nth() index")
            raise SoftEvalError.new("nth() index may not be 0") if n == 0
            idx = n > 0 ? n - 1 : items.size + n
            unless 0 <= idx < items.size
              raise SoftEvalError.new("nth() index #{n} is out of bounds for a #{items.size}-element list")
            end
            items[idx]
          end,
          "index" => Fn.new do |args, kwargs|
            args = args_with_kwargs("list.index", args, kwargs, %w[list value])
            arity!("index", args, 2)
            items = list_of(args[0])
            found = items.index(&.eq?(args[1]))
            found ? Number.new((found + 1).to_f, "") : NullV.new
          end,
          "append" => Fn.new do |args, kwargs|
            args = args_with_kwargs("list.append", args, kwargs, %w[list val separator])
            arity!("append", args, 2, 3)
            base = args[0]
            sep = base.is_a?(ListV) ? base.sep : ListV::Sep::Space
            bracketed = base.is_a?(ListV) && base.bracketed
            ListV.new(list_of(base) + [args[1]], sep_from(args[2]?, sep), bracketed)
          end,
          "join" => Fn.new do |args, kwargs|
            # `$separator` may be skipped when `$bracketed` is named.
            args = args_with_kwargs("list.join", args, kwargs, %w[list1 list2 separator bracketed],
              defaults: {2 => Str.new("auto", quoted: false).as(Value)})
            arity!("join", args, 2, 4)
            base = args[0]
            # `$separator: auto` takes $list1's separator, else $list2's,
            # else space. A scalar or a 0/1-element list carries no
            # meaningful separator, so committing to Space there turns the
            # accumulate-into-an-empty-list idiom into a space list.
            other = args[1]
            sep =
              if base.is_a?(ListV) && base.items.size > 1
                base.sep
              elsif other.is_a?(ListV) && other.items.size > 1
                other.sep
              else
                ListV::Sep::Space
              end
            # `$bracketed: auto` (the default) takes $list1's bracketing.
            bracketed =
              if (b = args[3]?) && !(b.is_a?(Str) && b.text == "auto")
                b.truthy?
              else
                base.is_a?(ListV) && base.bracketed
              end
            ListV.new(list_of(base) + list_of(args[1]), sep_from(args[2]?, sep), bracketed)
          end,
          "zip" => Fn.new do |args, kwargs|
            no_kwargs!("list.zip", kwargs)
            arity!("zip", args, 1, Int32::MAX)
            lists = args.map { |a| list_of(a) }
            size = lists.min_of(&.size)
            items = (0...size).map do |i|
              ListV.new(lists.map { |l| l[i] }, ListV::Sep::Space).as(Value)
            end
            ListV.new(items, ListV::Sep::Comma)
          end,
          "set-nth" => Fn.new do |args, kwargs|
            args = args_with_kwargs("list.set-nth", args, kwargs, %w[list n value])
            arity!("set-nth", args, 3)
            base = args[0]
            items = list_of(base).dup
            n = number!("set-nth", args[1]).int_value("set-nth() index")
            raise SoftEvalError.new("set-nth() index may not be 0") if n == 0
            idx = n > 0 ? n - 1 : items.size + n
            unless 0 <= idx < items.size
              raise SoftEvalError.new("set-nth() index #{n} is out of bounds for a #{items.size}-element list")
            end
            items[idx] = args[2]
            sep = base.is_a?(ListV) ? base.sep : ListV::Sep::Space
            bracketed = base.is_a?(ListV) && base.bracketed
            ListV.new(items, sep, bracketed)
          end,
          "slash" => Fn.new do |args, kwargs|
            no_kwargs!("list.slash", kwargs)
            arity!("list.slash", args, 2, Int32::MAX)
            ListV.new(args.dup, ListV::Sep::Slash)
          end,
          "is-bracketed" => Fn.new do |args, kwargs|
            args = args_with_kwargs("list.is-bracketed", args, kwargs, %w[list])
            arity!("is-bracketed", args, 1)
            value = args[0]
            BoolV.new(value.is_a?(ListV) && value.bracketed)
          end,
          "separator" => Fn.new do |args, kwargs|
            args = args_with_kwargs("list.separator", args, kwargs, %w[list])
            arity!("list-separator", args, 1)
            sep =
              case value = args[0]
              when ListV then value.sep
              else            ListV::Sep::Space
              end
            name =
              case sep
              in ListV::Sep::Comma then "comma"
              in ListV::Sep::Space then "space"
              in ListV::Sep::Slash then "slash"
              end
            Str.new(name, quoted: false)
          end,
        }

        # ---------------------------------------------------------------
        # sass:map
        # ---------------------------------------------------------------

        MAP_FNS = {
          "get" => Fn.new do |args, kwargs|
            args = args_with_kwargs("map.get", args, kwargs, %w[map key])
            arity!("map-get", args, 2, Int32::MAX)
            value = args[0].as(Value)
            # Extra keys drill into nested maps (dart-sass semantics); a
            # missing intermediate yields null, not an error.
            args[1..].each do |key|
              if value.is_a?(NullV)
                break
              end
              value = map!("map-get", value)[key]? || NullV.new
            end
            value
          end,
          "has-key" => Fn.new do |args, kwargs|
            args = args_with_kwargs("map.has-key", args, kwargs, %w[map key])
            arity!("map-has-key", args, 2, Int32::MAX)
            value = args[0].as(Value)
            found_all = true
            args[1..].each do |key|
              map = value.as?(MapV) ||
                    (value.is_a?(Raw) ? Expr.coerce(value.text).as?(MapV) : nil)
              unless map && (found = map[key]?)
                found_all = false
                break
              end
              value = found
            end
            BoolV.new(found_all)
          end,
          "keys" => Fn.new do |args, kwargs|
            args = args_with_kwargs("map.keys", args, kwargs, %w[map])
            arity!("map-keys", args, 1)
            ListV.new(map!("map-keys", args[0]).entries.map(&.key), ListV::Sep::Comma)
          end,
          "values" => Fn.new do |args, kwargs|
            args = args_with_kwargs("map.values", args, kwargs, %w[map])
            arity!("map-values", args, 1)
            ListV.new(map!("map-values", args[0]).entries.map(&.value), ListV::Sep::Comma)
          end,
          "merge" => Fn.new do |args, kwargs|
            args = args_with_kwargs("map.merge", args, kwargs, %w[map1 map2])
            arity!("map-merge", args, 2)
            base = map!("map-merge", args[0])
            overlay = map!("map-merge", args[1])
            entries = base.entries.dup
            overlay.entries.each do |entry|
              if idx = entries.index(&.key.eq?(entry.key))
                entries[idx] = entry
              else
                entries << entry
              end
            end
            MapV.new(entries)
          end,
          "remove" => Fn.new do |args, kwargs|
            args = args_with_kwargs("map.remove", args, kwargs, %w[map key])
            arity!("map-remove", args, 1, Int32::MAX)
            base = map!("map-remove", args[0])
            keys = args[1..]
            MapV.new(base.entries.reject { |e| keys.any?(&.eq?(e.key)) })
          end,
          "set" => Fn.new do |args, kwargs|
            no_kwargs!("map.set", kwargs)
            arity!("map.set", args, 3, Int32::MAX)
            # Intermediate keys drill into (or create) nested maps.
            map_set(map!("map.set", args[0]), args[1...-1], args[-1])
          end,
          "deep-merge" => Fn.new do |args, kwargs|
            args = args_with_kwargs("map.deep-merge", args, kwargs, %w[map1 map2])
            arity!("map.deep-merge", args, 2)
            map_deep_merge(map!("map.deep-merge", args[0]), map!("map.deep-merge", args[1]))
          end,
        }

        private def self.map_set(map : MapV, keys : Array(Value), value : Value) : MapV
          key = keys[0]
          entries = map.entries.dup
          replacement =
            if keys.size == 1
              value
            else
              inner = map[key]?
              inner_map = inner.as?(MapV) ||
                          (inner.is_a?(Raw) ? Expr.coerce(inner.text).as?(MapV) : nil) ||
                          MapV.new([] of MapEntry)
              map_set(inner_map, keys[1..], value)
            end
          if idx = entries.index(&.key.eq?(key))
            entries[idx] = MapEntry.new(key, replacement)
          else
            entries << MapEntry.new(key, replacement)
          end
          MapV.new(entries)
        end

        private def self.map_deep_merge(base : MapV, overlay : MapV) : MapV
          entries = base.entries.dup
          overlay.entries.each do |entry|
            idx = entries.index(&.key.eq?(entry.key))
            if idx && (existing = entries[idx].value.as?(MapV)) && (incoming = entry.value.as?(MapV))
              entries[idx] = MapEntry.new(entry.key, map_deep_merge(existing, incoming))
            elsif idx
              entries[idx] = entry
            else
              entries << entry
            end
          end
          MapV.new(entries)
        end

        # ---------------------------------------------------------------
        # sass:meta
        # ---------------------------------------------------------------

        META_FNS = {
          "type-of" => Fn.new do |args, kwargs|
            args = args_with_kwargs("meta.type-of", args, kwargs, %w[value])
            arity!("type-of", args, 1)
            name =
              case value = args[0]
              when Number then "number"
              when ColorV then "color"
              when BoolV  then "bool"
              when NullV  then "null"
              when ListV  then "list"
              when MapV   then "map"
              when Str
                # A bare ident can name a color (`red`); a quoted string
                # with the same text is just a string.
                !value.quoted && ColorV.parse?(value.text) ? "color" : "string"
              else
                # Raw soup: coerce for a better answer, else "string".
                value.is_a?(Raw) ? type_of_raw(value.text) : "string"
              end
            Str.new(name, quoted: false)
          end,
          "inspect" => Fn.new do |args, kwargs|
            args = args_with_kwargs("meta.inspect", args, kwargs, %w[value])
            arity!("inspect", args, 1)
            Str.new(inspect_value(args[0]), quoted: false)
          end,
        }

        private def self.type_of_raw(text : String) : String
          coerced = Expr.coerce(text)
          case coerced
          when Number then "number"
          when BoolV  then "bool"
          when NullV  then "null"
          when MapV   then "map"
          when ListV  then "list"
          else
            # Hex and named colors survive coercion as Raw; they are
            # colors, not strings.
            ColorV.parse?(text) ? "color" : "string"
          end
        end

        def self.inspect_value(value : Value) : String
          value.inspect_css
        end

        # ---------------------------------------------------------------
        # sass:color
        # ---------------------------------------------------------------

        # Shifts one HSL component and rebuilds the color.
        private def self.adjust_hsl(color : ColorV, hue : Float64 = 0.0,
                                    saturation : Float64 = 0.0,
                                    lightness : Float64 = 0.0) : ColorV
          h, s, l = color.to_hsl
          ColorV.from_hsl(h + hue, s + saturation, l + lightness, color.alpha)
        end

        # dart-sass's weighted mix. The alpha channels bias the RGB weights
        # so mixing into a translucent color doesn't wash it out: a fully
        # transparent operand contributes its hue proportionally less.
        private def self.mix_colors(color1 : ColorV, color2 : ColorV,
                                    weight : Float64) : ColorV
          weight_scale = weight / 100.0
          normalized = weight_scale * 2.0 - 1.0
          alpha_distance = color1.alpha - color2.alpha

          product = normalized * alpha_distance
          combined = product == -1.0 ? normalized : (normalized + alpha_distance) / (1.0 + product)

          weight1 = (combined + 1.0) / 2.0
          weight2 = 1.0 - weight1

          ColorV.new(
            color1.red * weight1 + color2.red * weight2,
            color1.green * weight1 + color2.green * weight2,
            color1.blue * weight1 + color2.blue * weight2,
            color1.alpha * weight_scale + color2.alpha * (1.0 - weight_scale)
          )
        end

        # `scale-color()` moves each component a percentage of the distance
        # to its own limit, so the result can never overshoot: +100% lands
        # exactly on the maximum, -100% on the minimum.
        private def self.scale_component(current : Float64, factor : Float64,
                                         max : Float64) : Float64
          if factor > 0
            current + (max - current) * (factor / 100.0)
          else
            current + current * (factor / 100.0)
          end
        end

        # RGB and HSL adjustments describe the same color two ways; letting
        # both through would make the result depend on which is applied
        # first, so dart-sass rejects the combination outright.
        private def self.reject_mixed_spaces!(name : String, rgb : Bool, hsl : Bool) : Nil
          return unless rgb && hsl
          raise SoftEvalError.new("#{name}() can't mix RGB and HSL arguments")
        end

        ADJUST_KWARGS = ["red", "green", "blue", "hue", "saturation", "lightness", "alpha"]
        SCALE_KWARGS  = ["red", "green", "blue", "saturation", "lightness", "alpha"]

        # How `adjust`/`scale`/`change` differ: each takes the current
        # component value and the requested amount and returns the new
        # value. Everything else about the three — argument binding, the
        # RGB/HSL exclusivity check, the alpha handling — is identical, so
        # they share `compound_color` below rather than three near-copies
        # that drift apart.
        enum ComponentMode
          Adjust
          Scale
          Change
        end

        private def self.combine(mode : ComponentMode, current : Float64,
                                 requested : Float64, max : Float64) : Float64
          case mode
          in ComponentMode::Adjust then current + requested
          in ComponentMode::Scale  then scale_component(current, requested, max)
          in ComponentMode::Change then requested
          end
        end

        # Range a component argument may occupy, which is the one thing the
        # three modes disagree on: `adjust` takes a signed delta, `scale` a
        # signed percentage, `change` an absolute value.
        private def self.component_range(mode : ComponentMode, max : Float64) : Tuple(Float64, Float64)
          case mode
          in ComponentMode::Adjust then {-max, max}
          in ComponentMode::Scale  then {-100.0, 100.0}
          in ComponentMode::Change then {0.0, max}
          end
        end

        private def self.compound_color(name : String, mode : ComponentMode,
                                        args : Array(Value), kwargs : Hash(String, Value)) : Value
          params = mode.scale? ? SCALE_KWARGS : ADJUST_KWARGS
          bound = bind!(name, args, kwargs, ["color"] + params, required: 1)
          color = color!(name, bound[0].as(Value))

          # `bound` is [color, *params]; re-key it by parameter name.
          given = {} of String => Value
          params.each_with_index { |param, index| (v = bound[index + 1]) && (given[param] = v) }
          red, green, blue = given["red"]?, given["green"]?, given["blue"]?
          hue, saturation, lightness = given["hue"]?, given["saturation"]?, given["lightness"]?
          alpha = given["alpha"]?

          reject_mixed_spaces!(name,
            !(red.nil? && green.nil? && blue.nil?),
            !(hue.nil? && saturation.nil? && lightness.nil?))

          result =
            if hue || saturation || lightness
              h, s, l = color.to_hsl
              # Hue is an angle, not a bounded component: it wraps rather
              # than clamping, and `scale` has no meaningful limit for it
              # (which is why $hue isn't in SCALE_KWARGS).
              if hue
                degrees = finite!(name, number!(name, hue))
                h = mode.change? ? degrees : h + degrees
              end
              if saturation
                min, max = component_range(mode, 100.0)
                s = combine(mode, s, amount!(name, saturation, min, max), 100.0)
              end
              if lightness
                min, max = component_range(mode, 100.0)
                l = combine(mode, l, amount!(name, lightness, min, max), 100.0)
              end
              ColorV.from_hsl(h, s, l, color.alpha)
            else
              min, max = component_range(mode, 255.0)
              ColorV.new(
                red ? combine(mode, color.red, amount!(name, red, min, max), 255.0) : color.red,
                green ? combine(mode, color.green, amount!(name, green, min, max), 255.0) : color.green,
                blue ? combine(mode, color.blue, amount!(name, blue, min, max), 255.0) : color.blue,
                color.alpha)
            end

          if alpha
            amin, amax = component_range(mode, 1.0)
            requested = mode.scale? ? amount!(name, alpha, amin, amax) : alpha!(name, alpha, amin, amax)
            result = result.with_alpha(combine(mode, result.alpha, requested, 1.0))
          end
          result
        end

        COLOR_FNS = {
          "adjust" => Fn.new do |args, kwargs|
            compound_color("color.adjust", ComponentMode::Adjust, args, kwargs)
          end,
          "scale" => Fn.new do |args, kwargs|
            compound_color("color.scale", ComponentMode::Scale, args, kwargs)
          end,
          "change" => Fn.new do |args, kwargs|
            compound_color("color.change", ComponentMode::Change, args, kwargs)
          end,
          "mix" => Fn.new do |args, kwargs|
            bound = bind!("mix", args, kwargs, ["color1", "color2", "weight"], required: 2)
            weight = (w = bound[2]) ? amount!("mix", w) : 50.0
            mix_colors(color!("mix", bound[0].as(Value)), color!("mix", bound[1].as(Value)), weight)
          end,
          "invert" => Fn.new do |args, kwargs|
            # `invert(20%)` is the CSS filter; only a color is ours.
            bound = shadowed_bind!("invert", args, kwargs, ["color", "weight"], required: 1)
            color = shadowed_color!(bound[0].as(Value))
            weight = (w = bound[1]) ? amount!("invert", w) : 100.0
            inverse = ColorV.new(255.0 - color.red, 255.0 - color.green,
              255.0 - color.blue, color.alpha)
            mix_colors(inverse, color, weight)
          end,
          "grayscale" => Fn.new do |args, kwargs|
            # `grayscale(50%)` is the CSS filter; only a color is ours.
            bound = shadowed_bind!("grayscale", args, kwargs, ["color"], required: 1)
            adjust_hsl(shadowed_color!(bound[0].as(Value)), saturation: -100.0)
          end,
          "complement" => Fn.new do |args, kwargs|
            bound = bind!("complement", args, kwargs, ["color"], required: 1)
            adjust_hsl(color!("complement", bound[0].as(Value)), hue: 180.0)
          end,
          "adjust-hue" => Fn.new do |args, kwargs|
            bound = bind!("adjust-hue", args, kwargs, ["color", "degrees"], required: 2)
            color = color!("adjust-hue", bound[0].as(Value))
            adjust_hsl(color, hue: finite!("adjust-hue", number!("adjust-hue", bound[1].as(Value))))
          end,
          "darken" => Fn.new do |args, kwargs|
            bound = bind!("darken", args, kwargs, ["color", "amount"], required: 2)
            color = color!("darken", bound[0].as(Value))
            adjust_hsl(color, lightness: -amount!("darken", bound[1].as(Value)))
          end,
          "lighten" => Fn.new do |args, kwargs|
            bound = bind!("lighten", args, kwargs, ["color", "amount"], required: 2)
            color = color!("lighten", bound[0].as(Value))
            adjust_hsl(color, lightness: amount!("lighten", bound[1].as(Value)))
          end,
          "saturate" => Fn.new do |args, kwargs|
            # One-argument `saturate(50%)` is the CSS filter, not this
            # function — decline so it stays verbatim.
            bound = shadowed_bind!("saturate", args, kwargs, ["color", "amount"], required: 2)
            color = shadowed_color!(bound[0].as(Value))
            adjust_hsl(color, saturation: amount!("saturate", bound[1].as(Value)))
          end,
          "desaturate" => Fn.new do |args, kwargs|
            bound = bind!("desaturate", args, kwargs, ["color", "amount"], required: 2)
            color = color!("desaturate", bound[0].as(Value))
            adjust_hsl(color, saturation: -amount!("desaturate", bound[1].as(Value)))
          end,
          "opacify" => Fn.new do |args, kwargs|
            bound = bind!("opacify", args, kwargs, ["color", "amount"], required: 2)
            color = color!("opacify", bound[0].as(Value))
            color.with_alpha(color.alpha + alpha!("opacify", bound[1].as(Value)))
          end,
          "transparentize" => Fn.new do |args, kwargs|
            bound = bind!("transparentize", args, kwargs, ["color", "amount"], required: 2)
            color = color!("transparentize", bound[0].as(Value))
            color.with_alpha(color.alpha - alpha!("transparentize", bound[1].as(Value)))
          end,
          "red" => Fn.new do |args, kwargs|
            bound = bind!("red", args, kwargs, ["color"], required: 1)
            Number.new(color!("red", bound[0].as(Value)).red8.to_f)
          end,
          "green" => Fn.new do |args, kwargs|
            bound = bind!("green", args, kwargs, ["color"], required: 1)
            Number.new(color!("green", bound[0].as(Value)).green8.to_f)
          end,
          "blue" => Fn.new do |args, kwargs|
            bound = bind!("blue", args, kwargs, ["color"], required: 1)
            Number.new(color!("blue", bound[0].as(Value)).blue8.to_f)
          end,
          "hue" => Fn.new do |args, kwargs|
            bound = bind!("hue", args, kwargs, ["color"], required: 1)
            Number.new(color!("hue", bound[0].as(Value)).hue, "deg")
          end,
          "saturation" => Fn.new do |args, kwargs|
            bound = bind!("saturation", args, kwargs, ["color"], required: 1)
            Number.new(color!("saturation", bound[0].as(Value)).saturation, "%")
          end,
          "lightness" => Fn.new do |args, kwargs|
            bound = bind!("lightness", args, kwargs, ["color"], required: 1)
            Number.new(color!("lightness", bound[0].as(Value)).lightness, "%")
          end,
          "alpha" => Fn.new do |args, kwargs|
            bound = bind!("alpha", args, kwargs, ["color"], required: 1)
            Number.new(color!("alpha", bound[0].as(Value)).alpha)
          end,
          "opacity" => Fn.new do |args, kwargs|
            # `opacity(50%)` is the CSS filter; only a color is ours.
            bound = shadowed_bind!("opacity", args, kwargs, ["color"], required: 1)
            Number.new(shadowed_color!(bound[0].as(Value)).alpha)
          end,
        }

        # `color.channel($color, $channel, $space: ...)` — the modern
        # accessor for single components. `$space` is accepted (rgb/hsl/
        # hwb spellings) but the channel name alone determines the answer;
        # colors here are always RGBA underneath.
        COLOR_FNS["channel"] = Fn.new do |args, kwargs|
          bound = bind!("color.channel", args, kwargs, ["color", "channel", "space"], required: 2)
          color = color!("color.channel", bound[0].as(Value))
          channel_arg = bound[1].as(Value)
          channel =
            case channel_arg
            when Str then channel_arg.text
            else          channel_arg.to_css
            end
          case ascii_downcase(channel)
          when "red"        then Number.new(color.red8.to_f)
          when "green"      then Number.new(color.green8.to_f)
          when "blue"       then Number.new(color.blue8.to_f)
          when "alpha"      then Number.new(color.alpha)
          when "hue"        then Number.new(color.hue, "deg")
          when "saturation" then Number.new(color.saturation, "%")
          when "lightness"  then Number.new(color.lightness, "%")
          when "whiteness"
            Number.new({color.red, color.green, color.blue}.min / 255.0 * 100.0, "%")
          when "blackness"
            Number.new((1.0 - {color.red, color.green, color.blue}.max / 255.0) * 100.0, "%")
          else
            raise SoftEvalError.new("color.channel(): unknown channel #{channel.inspect}")
          end
        end

        # `color.hwb($hue $whiteness $blackness)` — the space-separated
        # channels form. A slash-alpha (`… / 0.5`) is not modeled; use
        # `color.change($c, $alpha: …)` instead.
        COLOR_FNS["hwb"] = Fn.new do |args, kwargs|
          known_kwargs!("color.hwb", kwargs, ["channels"])
          arity!("color.hwb", args, 0, 1)
          channels = args[0]? || kwargs["channels"]? ||
                     raise SoftEvalError.new("color.hwb() is missing required argument $channels")
          items =
            case channels
            when ListV then channels.items
            else            raise SoftEvalError.new("color.hwb() expects a space-separated $hue $whiteness $blackness list")
            end
          arity!("color.hwb() channels", items, 3)
          hue = finite!("color.hwb", number!("color.hwb", items[0]))
          whiteness = amount!("color.hwb", items[1])
          blackness = amount!("color.hwb", items[2])
          Builtins.hwb_color(hue, whiteness, blackness)
        end

        # `ie-hex-str($color)` — the legacy `#AARRGGBB` spelling IE filters
        # take.
        IE_HEX_STR_FN = Fn.new do |args, kwargs|
          bound = bind!("ie-hex-str", args, kwargs, ["color"], required: 1)
          color = color!("ie-hex-str", bound[0].as(Value))
          alpha8 = ColorV.fuzzy_round(color.alpha * 255.0)
          Str.new("#%02X%02X%02X%02X" % {alpha8, color.red8, color.green8, color.blue8},
            quoted: false)
        end
        COLOR_FNS["ie-hex-str"] = IE_HEX_STR_FN

        # HWB → RGB (CSS Color 4): degenerate w+b ≥ 100 is a flat gray,
        # otherwise the pure hue scaled between whiteness and blackness.
        def self.hwb_color(hue : Float64, whiteness : Float64, blackness : Float64) : ColorV
          w = whiteness / 100.0
          b = blackness / 100.0
          if w + b >= 1.0
            gray = w / (w + b) * 255.0
            return ColorV.new(gray, gray, gray)
          end
          pure = ColorV.from_hsl(hue, 100.0, 50.0)
          scale = ->(channel : Float64) { (channel / 255.0 * (1.0 - w - b) + w) * 255.0 }
          ColorV.new(scale.call(pure.red), scale.call(pure.green), scale.call(pure.blue))
        end

        # `color.fade-in` / `color.fade-out` are the module spellings of
        # opacify / transparentize. dart-sass defines both, so the module
        # table needs them or `color.fade-in(...)` leaks its call text.
        COLOR_FNS["fade-in"] = COLOR_FNS["opacify"]
        COLOR_FNS["fade-out"] = COLOR_FNS["transparentize"]

        # `rgba($color, $alpha)` / `rgb($color, $alpha)` — the Sass-only
        # two-argument spelling. Every other shape (`rgb(0, 0, 0)`,
        # `rgb(0 0 0 / 50%)`, relative color syntax) is real CSS, so those
        # decline with ShapeMismatch and reconstruct verbatim instead of
        # unwinding the whole declaration.
        RGBA_FN = Fn.new do |args, kwargs|
          bound = shadowed_bind!("rgba", args, kwargs, ["color", "alpha"], required: 2)
          color = shadowed_color!(bound[0].as(Value))
          color.with_alpha(alpha!("rgba", bound[1].as(Value)))
        end

        # ---------------------------------------------------------------
        # sass:selector
        #
        # String-level implementations of the selector functions: selectors
        # are comma lists of complex selectors, tokenized with the same
        # quote/bracket/paren-aware parser @extend uses. Sound for the
        # class/id/element/pseudo/attribute selectors frameworks feed
        # these; the full unification semantics (combinator weaving,
        # pseudo-element rules) are out of scope.
        # ---------------------------------------------------------------

        # A selector argument as text: strings/raw verbatim, lists joined
        # by their separator (`&` arrives as a comma list of strings).
        private def self.selector_text(name : String, value : Value) : String
          case value
          when Str   then value.text
          when Raw   then value.text
          when ListV then value.items.map { |i| selector_text(name, i) }.join(value.sep == ListV::Sep::Comma ? ", " : " ")
          when NullV then raise SoftEvalError.new("#{name}: expected a selector, got null")
          else
            raise SoftEvalError.new("#{name}: expected a selector, got #{value.to_css.inspect}")
          end
        end

        # Comma list of complex selectors, each an array of compounds and
        # combinators. Attribute selectors and `:is()`/`:not()` parens keep
        # their internal whitespace — naive String#split would fragment
        # `[title="a b"]` into two tokens.
        private def self.selector_complexes(name : String, value : Value) : Array(Array(String))
          Parser.split_top_level_commas(selector_text(name, value)).map(&.strip).reject(&.empty?).map do |complex|
            items = Extend.parse_items(complex)
            raise SoftEvalError.new("#{name}: invalid selector #{complex.inspect}") unless items
            items.map do |item|
              case item
              in Extend::Combinator then item.text
              in Extend::Compound   then item.simples.join
              end
            end
          end
        end

        # Splits one compound selector into its leading element (or "") and
        # the trailing simple selectors (classes, ids, attributes, pseudos,
        # placeholders).
        private def self.compound_simples(compound : String) : {String, Array(String)}
          simples = [] of String
          element = String::Builder.new
          i = 0
          chars = compound.chars
          while i < chars.size && !".#:[%".includes?(chars[i])
            element << chars[i]
            i += 1
          end
          while i < chars.size
            start = i
            i += 1                     # the delimiter
            i += 1 if chars[i]? == ':' # `::pseudo-element`
            depth = 0
            while i < chars.size
              c = chars[i]
              if c == '(' || c == '['
                depth += 1
              elsif c == ')' || c == ']'
                depth -= 1
                i += 1
                break if depth == 0 && (chars[i]?.nil? || ".#:[%".includes?(chars[i]))
                next
              elsif depth == 0 && ".#:[%".includes?(c) && !(c == ':' && chars[start] == ':' && i == start + 1)
                break
              end
              i += 1
            end
            simples << chars[start...i].join
          end
          {element.to_s, simples}
        end

        # Merges two compound selectors into one matching both, or nil when
        # they can't both match (two different element types).
        private def self.unify_compounds(a : String, b : String) : String?
          ea, sa = compound_simples(a)
          eb, sb = compound_simples(b)
          element =
            if ea.empty? || ea == "*"
              eb.empty? ? ea : eb
            elsif eb.empty? || eb == "*"
              ea
            elsif ea == eb
              ea
            else
              return
            end
          merged = sa.dup
          sb.each { |s| merged << s unless merged.includes?(s) }
          # Pseudo-classes/-elements sort after the other simple selectors
          # (dart's compound ordering, same rule Extend.unify_compound
          # documents): `.x:hover` + `.z` is `.x.z:hover`.
          plain, pseudo = merged.partition { |s| !s.starts_with?(':') }
          element + (plain + pseudo).join
        end

        # True when every element `sub` matches is also matched by `sup`
        # (subset simples, compounds embedded in order, last-to-last).
        private def self.complex_superselector?(sup : Array(String), sub : Array(String)) : Bool
          sup_c = sup.reject { |w| w == ">" || w == "+" || w == "~" }
          sub_c = sub.reject { |w| w == ">" || w == "+" || w == "~" }
          return false if sup_c.empty? || sub_c.empty?
          return false unless compound_subset?(sup_c.last, sub_c.last)
          si = 0
          sup_c[0...-1].each do |sc|
            while si < sub_c.size - 1 && !compound_subset?(sc, sub_c[si])
              si += 1
            end
            return false if si >= sub_c.size - 1
            si += 1
          end
          true
        end

        private def self.compound_subset?(a : String, b : String) : Bool
          ea, sa = compound_simples(a)
          eb, sb = compound_simples(b)
          element_ok = ea.empty? || ea == "*" || ea == eb
          element_ok && sa.all? { |s| sb.includes?(s) }
        end

        private def self.selector_value(complexes : Array(Array(String))) : Value
          items = complexes.map do |words|
            ListV.new(words.map { |w| Str.new(w, quoted: false).as(Value) }, ListV::Sep::Space).as(Value)
          end
          ListV.new(items, ListV::Sep::Comma)
        end

        SELECTOR_FNS = {
          "parse" => Fn.new do |args, kwargs|
            args = args_with_kwargs("selector.parse", args, kwargs, %w[selector])
            arity!("selector-parse", args, 1)
            selector_value(selector_complexes("selector.parse()", args[0]))
          end,
          "nest" => Fn.new do |args, kwargs|
            no_kwargs!("selector.nest", kwargs)
            arity!("selector-nest", args, 1, Int32::MAX)
            result = selector_complexes("selector.nest()", args[0])
            args[1..].each do |arg|
              parts = selector_complexes("selector.nest()", arg)
              grown = [] of Array(String)
              result.each do |parent|
                parent_text = parent.join(' ')
                parts.each do |part|
                  if part.any?(&.includes?('&'))
                    grown << part.flat_map(&.gsub('&', parent_text).split)
                  else
                    grown << parent + part
                  end
                end
              end
              result = grown
            end
            selector_value(result)
          end,
          "append" => Fn.new do |args, kwargs|
            no_kwargs!("selector.append", kwargs)
            arity!("selector-append", args, 1, Int32::MAX)
            result = selector_complexes("selector.append()", args[0])
            args[1..].each do |arg|
              parts = selector_complexes("selector.append()", arg)
              grown = [] of Array(String)
              result.each do |parent|
                parts.each do |part|
                  head = part[0]
                  if [">", "+", "~"].includes?(head) || [">", "+", "~"].includes?(parent.last)
                    raise SoftEvalError.new("selector.append(): can't append #{part.join(' ').inspect}")
                  end
                  grown << parent[0...-1] + [parent.last + head] + part[1..]
                end
              end
              result = grown
            end
            selector_value(result)
          end,
          "unify" => Fn.new do |args, kwargs|
            args = args_with_kwargs("selector.unify", args, kwargs, %w[selector1 selector2])
            arity!("selector-unify", args, 2)
            a_list = selector_complexes("selector.unify()", args[0])
            b_list = selector_complexes("selector.unify()", args[1])
            unified = [] of Array(String)
            a_list.each do |a|
              b_list.each do |b|
                merged = unify_compounds(a.last, b.last)
                next unless merged
                unified << a[0...-1] + b[0...-1] + [merged]
              end
            end
            next NullV.new.as(Value) if unified.empty?
            selector_value(unified)
          end,
          "is-superselector" => Fn.new do |args, kwargs|
            args = args_with_kwargs("selector.is-superselector", args, kwargs, %w[super sub])
            arity!("is-superselector", args, 2)
            supers = selector_complexes("is-superselector()", args[0])
            subs = selector_complexes("is-superselector()", args[1])
            BoolV.new(subs.all? do |sub|
              supers.any? { |sup| complex_superselector?(sup, sub) }
            end)
          end,
          "simple-selectors" => Fn.new do |args, kwargs|
            args = args_with_kwargs("selector.simple-selectors", args, kwargs, %w[selector])
            arity!("simple-selectors", args, 1)
            complexes = selector_complexes("selector.simple-selectors()", args[0])
            unless complexes.size == 1 && complexes[0].size == 1
              raise SoftEvalError.new("selector.simple-selectors() expects a compound selector, got #{args[0].to_css.inspect}")
            end
            element, simples = compound_simples(complexes[0][0])
            names = [] of String
            names << element unless element.empty?
            names.concat(simples)
            ListV.new(names.map { |n| Str.new(n, quoted: false).as(Value) }, ListV::Sep::Comma)
          end,
          "replace" => Fn.new do |args, kwargs|
            args = args_with_kwargs("selector.replace", args, kwargs, %w[selector original replacement])
            arity!("selector-replace", args, 3)
            selector_value(selector_replace("selector.replace()", args[0], args[1], args[2]))
          end,
        }

        # `selector.replace`: within each compound of $selector that
        # contains all of $original's simple selectors, remove them and
        # unify what's left with $replacement (extend-style semantics for
        # the practical case: single-compound $original, $replacement
        # complexes whose leading compounds splice in before the match).
        private def self.selector_replace(name : String, selector : Value,
                                          original : Value, replacement : Value) : Array(Array(String))
          originals = selector_complexes(name, original)
          replacements = selector_complexes(name, replacement)
          if originals.any? { |o| o.size != 1 }
            raise SoftEvalError.new("#{name}: $original must be a compound selector")
          end
          result = [] of Array(String)
          selector_complexes(name, selector).each do |complex|
            # EVERY matching compound in the complex is replaced (dart:
            # `.b .b` with `.b` → `.c` yields the single `.c .c`, not one
            # variant per occurrence). Multiple replacement complexes
            # cross-multiply across the matched positions.
            variants = [complex]
            # Right-to-left so a replacement whose complex has extra
            # leading compounds doesn't shift the not-yet-visited indices.
            (complex.size - 1).downto(0) do |index|
              word = complex[index]
              next if word == ">" || word == "+" || word == "~"
              orig = originals.find { |o| compound_subset?(o[0], word) }
              next unless orig
              stripped = compound_strip(word, orig[0])
              grown = [] of Array(String)
              variants.each do |variant|
                replacements.each do |repl|
                  merged = stripped.empty? ? repl.last : unify_compounds(stripped, repl.last)
                  next unless merged
                  grown << variant[0...index] + repl[0...-1] + [merged] + variant[index + 1..]
                end
              end
              # A matched compound whose replacement can't unify
              # eliminates the variant (dart-sass fails the build when
              # nothing is left — `selector.replace("a.foo", ".foo",
              # "h1")` must not return `a.foo` with the target intact).
              variants = grown
            end
            result.concat(variants)
          end
          if result.empty?
            raise SoftEvalError.new(
              "#{name}: $replacement can't be unified with $selector")
          end
          result
        end

        # The compound minus every simple selector `original` mentions
        # ("" when nothing is left).
        private def self.compound_strip(compound : String, original : String) : String
          element, simples = compound_simples(compound)
          orig_element, orig_simples = compound_simples(original)
          element = "" if !orig_element.empty? && element == orig_element
          element + simples.reject { |s| orig_simples.includes?(s) }.join
        end

        # ---------------------------------------------------------------
        # Global names (dart-sass legacy globals) + `if()`
        # ---------------------------------------------------------------

        IF_FN = Fn.new do |args, kwargs|
          no_kwargs!("if", kwargs)
          arity!("if", args, 3)
          args[0].truthy? ? args[1] : args[2]
        end

        GLOBAL_FNS = {
          "if"             => IF_FN,
          "quote"          => STRING_FNS["quote"],
          "unquote"        => STRING_FNS["unquote"],
          "str-length"     => STRING_FNS["length"],
          "str-index"      => STRING_FNS["index"],
          "str-slice"      => STRING_FNS["slice"],
          "str-insert"     => STRING_FNS["insert"],
          "to-upper-case"  => STRING_FNS["to-upper-case"],
          "to-lower-case"  => STRING_FNS["to-lower-case"],
          "length"         => LIST_FNS["length"],
          "nth"            => LIST_FNS["nth"],
          "index"          => LIST_FNS["index"],
          "append"         => LIST_FNS["append"],
          "join"           => LIST_FNS["join"],
          "zip"            => LIST_FNS["zip"],
          "set-nth"        => LIST_FNS["set-nth"],
          "is-bracketed"   => LIST_FNS["is-bracketed"],
          "list-separator" => LIST_FNS["separator"],
          "map-get"        => MAP_FNS["get"],
          "map-has-key"    => MAP_FNS["has-key"],
          "map-keys"       => MAP_FNS["keys"],
          "map-values"     => MAP_FNS["values"],
          "map-merge"      => MAP_FNS["merge"],
          "map-remove"     => MAP_FNS["remove"],
          "percentage"     => MATH_FNS["percentage"],
          "round"          => MATH_FNS["round"],
          "ceil"           => MATH_FNS["ceil"],
          "floor"          => MATH_FNS["floor"],
          "abs"            => MATH_FNS["abs"],
          "min"            => MATH_FNS["min"],
          "max"            => MATH_FNS["max"],
          "unit"           => MATH_FNS["unit"],
          "unitless"       => MATH_FNS["is-unitless"],
          "comparable"     => MATH_FNS["compatible"],
          "type-of"        => META_FNS["type-of"],
          "inspect"        => META_FNS["inspect"],
          "darken"         => COLOR_FNS["darken"],
          "lighten"        => COLOR_FNS["lighten"],
          "saturate"       => COLOR_FNS["saturate"],
          "desaturate"     => COLOR_FNS["desaturate"],
          "grayscale"      => COLOR_FNS["grayscale"],
          "greyscale"      => COLOR_FNS["grayscale"],
          "complement"     => COLOR_FNS["complement"],
          "adjust-hue"     => COLOR_FNS["adjust-hue"],
          "invert"         => COLOR_FNS["invert"],
          "mix"            => COLOR_FNS["mix"],
          "adjust-color"   => COLOR_FNS["adjust"],
          "scale-color"    => COLOR_FNS["scale"],
          "change-color"   => COLOR_FNS["change"],
          "opacify"        => COLOR_FNS["opacify"],
          "fade-in"        => COLOR_FNS["opacify"],
          "transparentize" => COLOR_FNS["transparentize"],
          "fade-out"       => COLOR_FNS["transparentize"],
          "red"            => COLOR_FNS["red"],
          "green"          => COLOR_FNS["green"],
          "blue"           => COLOR_FNS["blue"],
          "hue"            => COLOR_FNS["hue"],
          "saturation"     => COLOR_FNS["saturation"],
          "lightness"      => COLOR_FNS["lightness"],
          "alpha"          => COLOR_FNS["alpha"],
          "opacity"        => COLOR_FNS["opacity"],
          "ie-hex-str"     => IE_HEX_STR_FN,
          "rgba"           => RGBA_FN,
          "rgb"            => RGBA_FN,
          # Legacy global selector functions.
          "selector-parse"   => SELECTOR_FNS["parse"],
          "selector-nest"    => SELECTOR_FNS["nest"],
          "selector-append"  => SELECTOR_FNS["append"],
          "selector-unify"   => SELECTOR_FNS["unify"],
          "selector-replace" => SELECTOR_FNS["replace"],
          "is-superselector" => SELECTOR_FNS["is-superselector"],
          "simple-selectors" => SELECTOR_FNS["simple-selectors"],
        }

        # `sass:<name>` module tables: {functions, variables}.
        MODULE_TABLES = {
          "math"     => {MATH_FNS, MATH_VARS},
          "string"   => {STRING_FNS, {} of String => String},
          "list"     => {LIST_FNS, {} of String => String},
          "map"      => {MAP_FNS, {} of String => String},
          "meta"     => {META_FNS, {} of String => String},
          "color"    => {COLOR_FNS, {} of String => String},
          "selector" => {SELECTOR_FNS, {} of String => String},
        }
      end
    end
  end
end
