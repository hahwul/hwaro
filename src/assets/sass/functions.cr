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

        private def self.same_units!(name : String, numbers : Array(Number)) : String
          unit = ""
          numbers.each do |n|
            next if n.unit.empty?
            if unit.empty?
              unit = n.unit
            elsif unit != n.unit
              raise SoftEvalError.new("#{name}(): incompatible units #{unit} and #{n.unit}")
            end
          end
          unit
        end

        # ---------------------------------------------------------------
        # sass:math
        # ---------------------------------------------------------------

        MATH_FNS = {
          "div" => Fn.new do |args, kwargs|
            no_kwargs!("math.div", kwargs)
            arity!("math.div", args, 2)
            a = number!("math.div", args[0])
            b = number!("math.div", args[1])
            raise SoftEvalError.new("math.div(): division by zero") if b.value == 0
            unit =
              if a.unit == b.unit
                "" # units cancel
              elsif b.unit.empty?
                a.unit
              elsif a.unit.empty?
                raise SoftEvalError.new("math.div(): can't divide unitless by #{b.unit}")
              else
                raise SoftEvalError.new("math.div(): incompatible units #{a.unit} and #{b.unit}")
              end
            Number.new(a.value / b.value, unit)
          end,
          "percentage" => Fn.new do |args, kwargs|
            no_kwargs!("math.percentage", kwargs)
            arity!("math.percentage", args, 1)
            n = number!("math.percentage", args[0])
            unless n.unit.empty?
              raise SoftEvalError.new("math.percentage() expects a unitless number, got #{n.to_css}")
            end
            Number.new(n.value * 100, "%")
          end,
          "round" => Fn.new do |args, kwargs|
            no_kwargs!("math.round", kwargs)
            arity!("round", args, 1)
            n = number!("round", args[0])
            # Sass rounds halves away from zero; Crystal's default is
            # banker's rounding, which sends round(2.5) to 2.
            Number.new(n.value.round(mode: :ties_away).to_f, n.unit)
          end,
          "ceil" => Fn.new do |args, kwargs|
            no_kwargs!("math.ceil", kwargs)
            arity!("ceil", args, 1)
            n = number!("ceil", args[0])
            Number.new(n.value.ceil.to_f, n.unit)
          end,
          "floor" => Fn.new do |args, kwargs|
            no_kwargs!("math.floor", kwargs)
            arity!("floor", args, 1)
            n = number!("floor", args[0])
            Number.new(n.value.floor.to_f, n.unit)
          end,
          "abs" => Fn.new do |args, kwargs|
            no_kwargs!("math.abs", kwargs)
            arity!("abs", args, 1)
            n = number!("abs", args[0])
            Number.new(n.value.abs, n.unit)
          end,
          "min" => Fn.new do |args, kwargs|
            no_kwargs!("math.min", kwargs)
            arity!("min", args, 1, Int32::MAX)
            numbers = args.map { |a| number!("min", a) }
            same_units!("min", numbers) # unit-compatibility check only
            # Return the winning operand as-is. Stamping the first non-empty
            # unit seen across all args onto the winner fabricates a unit
            # the result never had: `min(1, 2px)` is `1`, not `1px`.
            winner = numbers.min_by(&.value)
            Number.new(winner.value, winner.unit)
          end,
          "max" => Fn.new do |args, kwargs|
            no_kwargs!("math.max", kwargs)
            arity!("max", args, 1, Int32::MAX)
            numbers = args.map { |a| number!("max", a) }
            same_units!("max", numbers) # unit-compatibility check only
            winner = numbers.max_by(&.value)
            Number.new(winner.value, winner.unit)
          end,
          "clamp" => Fn.new do |args, kwargs|
            no_kwargs!("math.clamp", kwargs)
            arity!("math.clamp", args, 3)
            numbers = args.map { |a| number!("math.clamp", a) }
            same_units!("math.clamp", numbers) # unit-compatibility check only
            # As with min/max, the result is whichever operand wins, unit
            # included — not the value re-stamped with a scanned unit.
            low, mid, high = numbers[0], numbers[1], numbers[2]
            winner = mid.value < low.value ? low : (mid.value > high.value ? high : mid)
            Number.new(winner.value, winner.unit)
          end,
          "pow" => Fn.new do |args, kwargs|
            no_kwargs!("math.pow", kwargs)
            arity!("math.pow", args, 2)
            base = number!("math.pow", args[0])
            exp = number!("math.pow", args[1])
            unless base.unit.empty? && exp.unit.empty?
              raise SoftEvalError.new("math.pow() expects unitless numbers")
            end
            Number.new(base.value ** exp.value, "")
          end,
          "sqrt" => Fn.new do |args, kwargs|
            no_kwargs!("math.sqrt", kwargs)
            arity!("math.sqrt", args, 1)
            n = number!("math.sqrt", args[0])
            unless n.unit.empty?
              raise SoftEvalError.new("math.sqrt() expects a unitless number")
            end
            raise SoftEvalError.new("math.sqrt() of a negative number") if n.value < 0
            Number.new(Math.sqrt(n.value), "")
          end,
          "unit" => Fn.new do |args, kwargs|
            no_kwargs!("math.unit", kwargs)
            arity!("unit", args, 1)
            Str.new(number!("unit", args[0]).unit, quoted: true)
          end,
          "is-unitless" => Fn.new do |args, kwargs|
            no_kwargs!("math.is-unitless", kwargs)
            arity!("unitless", args, 1)
            BoolV.new(number!("unitless", args[0]).unit.empty?)
          end,
          "compatible" => Fn.new do |args, kwargs|
            no_kwargs!("math.compatible", kwargs)
            arity!("comparable", args, 2)
            a = number!("comparable", args[0])
            b = number!("comparable", args[1])
            BoolV.new(a.compatible_unit?(b))
          end,
        }

        MATH_VARS = {
          "pi" => "3.1415926536",
          "e"  => "2.7182818285",
        }

        # ---------------------------------------------------------------
        # sass:string
        # ---------------------------------------------------------------

        STRING_FNS = {
          "quote" => Fn.new do |args, kwargs|
            no_kwargs!("string.quote", kwargs)
            arity!("quote", args, 1)
            s = string!("quote", args[0])
            Str.new(s.text, quoted: true)
          end,
          "unquote" => Fn.new do |args, kwargs|
            no_kwargs!("string.unquote", kwargs)
            arity!("unquote", args, 1)
            s = string!("unquote", args[0])
            Str.new(s.text, quoted: false)
          end,
          "length" => Fn.new do |args, kwargs|
            no_kwargs!("string.length", kwargs)
            arity!("str-length", args, 1)
            Number.new(string!("str-length", args[0]).text.size.to_f, "")
          end,
          "index" => Fn.new do |args, kwargs|
            no_kwargs!("string.index", kwargs)
            arity!("str-index", args, 2)
            haystack = string!("str-index", args[0]).text
            needle = string!("str-index", args[1]).text
            idx = haystack.index(needle)
            idx ? Number.new((idx + 1).to_f, "") : NullV.new
          end,
          "slice" => Fn.new do |args, kwargs|
            no_kwargs!("string.slice", kwargs)
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
          "to-upper-case" => Fn.new do |args, kwargs|
            no_kwargs!("string.to-upper-case", kwargs)
            arity!("to-upper-case", args, 1)
            s = string!("to-upper-case", args[0])
            # Sass maps ASCII only; Crystal's `upcase` is Unicode-aware.
            Str.new(ascii_upcase(s.text), quoted: s.quoted, quote_char: s.quote_char)
          end,
          "to-lower-case" => Fn.new do |args, kwargs|
            no_kwargs!("string.to-lower-case", kwargs)
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
            no_kwargs!("list.length", kwargs)
            arity!("length", args, 1)
            Number.new(list_of(args[0]).size.to_f, "")
          end,
          "nth" => Fn.new do |args, kwargs|
            no_kwargs!("list.nth", kwargs)
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
            no_kwargs!("list.index", kwargs)
            arity!("index", args, 2)
            items = list_of(args[0])
            found = items.index(&.eq?(args[1]))
            found ? Number.new((found + 1).to_f, "") : NullV.new
          end,
          "append" => Fn.new do |args, kwargs|
            no_kwargs!("list.append", kwargs)
            arity!("append", args, 2, 3)
            base = args[0]
            sep = base.is_a?(ListV) ? base.sep : ListV::Sep::Space
            bracketed = base.is_a?(ListV) && base.bracketed
            ListV.new(list_of(base) + [args[1]], sep_from(args[2]?, sep), bracketed)
          end,
          "join" => Fn.new do |args, kwargs|
            no_kwargs!("list.join", kwargs)
            arity!("join", args, 2, 3)
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
            bracketed = base.is_a?(ListV) && base.bracketed
            ListV.new(list_of(base) + list_of(args[1]), sep_from(args[2]?, sep), bracketed)
          end,
          "separator" => Fn.new do |args, kwargs|
            no_kwargs!("list.separator", kwargs)
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
            no_kwargs!("map.get", kwargs)
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
            no_kwargs!("map.has-key", kwargs)
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
            no_kwargs!("map.keys", kwargs)
            arity!("map-keys", args, 1)
            ListV.new(map!("map-keys", args[0]).entries.map(&.key), ListV::Sep::Comma)
          end,
          "values" => Fn.new do |args, kwargs|
            no_kwargs!("map.values", kwargs)
            arity!("map-values", args, 1)
            ListV.new(map!("map-values", args[0]).entries.map(&.value), ListV::Sep::Comma)
          end,
          "merge" => Fn.new do |args, kwargs|
            no_kwargs!("map.merge", kwargs)
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
            no_kwargs!("map.remove", kwargs)
            arity!("map-remove", args, 1, Int32::MAX)
            base = map!("map-remove", args[0])
            keys = args[1..]
            MapV.new(base.entries.reject { |e| keys.any?(&.eq?(e.key)) })
          end,
        }

        # ---------------------------------------------------------------
        # sass:meta
        # ---------------------------------------------------------------

        META_FNS = {
          "type-of" => Fn.new do |args, kwargs|
            no_kwargs!("meta.type-of", kwargs)
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
            no_kwargs!("meta.inspect", kwargs)
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
          "to-upper-case"  => STRING_FNS["to-upper-case"],
          "to-lower-case"  => STRING_FNS["to-lower-case"],
          "length"         => LIST_FNS["length"],
          "nth"            => LIST_FNS["nth"],
          "index"          => LIST_FNS["index"],
          "append"         => LIST_FNS["append"],
          "join"           => LIST_FNS["join"],
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
          "rgba"           => RGBA_FN,
          "rgb"            => RGBA_FN,
        }

        # `sass:<name>` module tables: {functions, variables}.
        MODULE_TABLES = {
          "math"   => {MATH_FNS, MATH_VARS},
          "string" => {STRING_FNS, {} of String => String},
          "list"   => {LIST_FNS, {} of String => String},
          "map"    => {MAP_FNS, {} of String => String},
          "meta"   => {META_FNS, {} of String => String},
          "color"  => {COLOR_FNS, {} of String => String},
        }
      end
    end
  end
end
