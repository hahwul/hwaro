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

        # Percentage-style amount (`10%` or bare `10`). Sass treats the
        # unit as decorative here; what matters is the 0..100 magnitude.
        private def self.amount!(name : String, value : Value,
                                 min : Float64 = 0.0, max : Float64 = 100.0) : Float64
          number!(name, value).value.clamp(min, max)
        end

        # Alpha-style amount, on 0..1. A percentage spelling (`50%`) is
        # accepted and scaled, matching dart-sass.
        private def self.alpha!(name : String, value : Value,
                                min : Float64 = 0.0, max : Float64 = 1.0) : Float64
          n = number!(name, value)
          raw = n.unit == "%" ? n.value / 100.0 : n.value
          raw.clamp(min, max)
        end

        # Named argument lookup that tolerates the `$foo-bar` / `$foo_bar`
        # spellings Sass treats as one name.
        private def self.kwarg?(kwargs : Hash(String, Value), name : String) : Value?
          kwargs[name]? || kwargs[name.tr("-", "_")]? || kwargs[name.tr("_", "-")]?
        end

        # Rejects keyword arguments the function doesn't define, so a typo
        # (`$lightnes:`) fails loudly instead of being silently dropped.
        private def self.known_kwargs!(name : String, kwargs : Hash(String, Value),
                                       allowed : Array(String)) : Nil
          kwargs.each_key do |key|
            normalized = key.tr("_", "-")
            next if allowed.includes?(normalized)
            raise SoftEvalError.new("#{name}() has no argument named $#{key}")
          end
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

        COLOR_FNS = {
          "adjust" => Fn.new do |args, kwargs|
            arity!("color.adjust", args, 1)
            known_kwargs!("color.adjust", kwargs, ADJUST_KWARGS)
            color = color!("color.adjust", args[0])

            red = kwarg?(kwargs, "red")
            green = kwarg?(kwargs, "green")
            blue = kwarg?(kwargs, "blue")
            hue = kwarg?(kwargs, "hue")
            saturation = kwarg?(kwargs, "saturation")
            lightness = kwarg?(kwargs, "lightness")
            alpha = kwarg?(kwargs, "alpha")
            reject_mixed_spaces!("color.adjust",
              !(red.nil? && green.nil? && blue.nil?),
              !(hue.nil? && saturation.nil? && lightness.nil?))

            result =
              if hue || saturation || lightness
                adjust_hsl(color,
                  hue: hue ? number!("color.adjust", hue).value : 0.0,
                  saturation: saturation ? amount!("color.adjust", saturation, -100.0) : 0.0,
                  lightness: lightness ? amount!("color.adjust", lightness, -100.0) : 0.0)
              else
                ColorV.new(
                  color.red + (red ? amount!("color.adjust", red, -255.0, 255.0) : 0.0),
                  color.green + (green ? amount!("color.adjust", green, -255.0, 255.0) : 0.0),
                  color.blue + (blue ? amount!("color.adjust", blue, -255.0, 255.0) : 0.0),
                  color.alpha)
              end
            result = result.with_alpha(result.alpha + alpha!("color.adjust", alpha, -1.0)) if alpha
            result
          end,
          "scale" => Fn.new do |args, kwargs|
            arity!("color.scale", args, 1)
            known_kwargs!("color.scale", kwargs, SCALE_KWARGS)
            color = color!("color.scale", args[0])

            red = kwarg?(kwargs, "red")
            green = kwarg?(kwargs, "green")
            blue = kwarg?(kwargs, "blue")
            saturation = kwarg?(kwargs, "saturation")
            lightness = kwarg?(kwargs, "lightness")
            alpha = kwarg?(kwargs, "alpha")
            reject_mixed_spaces!("color.scale",
              !(red.nil? && green.nil? && blue.nil?),
              !(saturation.nil? && lightness.nil?))

            result =
              if saturation || lightness
                h, s, l = color.to_hsl
                s = scale_component(s, amount!("color.scale", saturation, -100.0), 100.0) if saturation
                l = scale_component(l, amount!("color.scale", lightness, -100.0), 100.0) if lightness
                ColorV.from_hsl(h, s, l, color.alpha)
              else
                ColorV.new(
                  red ? scale_component(color.red, amount!("color.scale", red, -100.0), 255.0) : color.red,
                  green ? scale_component(color.green, amount!("color.scale", green, -100.0), 255.0) : color.green,
                  blue ? scale_component(color.blue, amount!("color.scale", blue, -100.0), 255.0) : color.blue,
                  color.alpha)
              end
            if alpha
              scaled = scale_component(result.alpha, amount!("color.scale", alpha, -100.0), 1.0)
              result = result.with_alpha(scaled)
            end
            result
          end,
          "change" => Fn.new do |args, kwargs|
            arity!("color.change", args, 1)
            known_kwargs!("color.change", kwargs, ADJUST_KWARGS)
            color = color!("color.change", args[0])

            red = kwarg?(kwargs, "red")
            green = kwarg?(kwargs, "green")
            blue = kwarg?(kwargs, "blue")
            hue = kwarg?(kwargs, "hue")
            saturation = kwarg?(kwargs, "saturation")
            lightness = kwarg?(kwargs, "lightness")
            alpha = kwarg?(kwargs, "alpha")
            reject_mixed_spaces!("color.change",
              !(red.nil? && green.nil? && blue.nil?),
              !(hue.nil? && saturation.nil? && lightness.nil?))

            result =
              if hue || saturation || lightness
                h, s, l = color.to_hsl
                h = number!("color.change", hue).value if hue
                s = amount!("color.change", saturation) if saturation
                l = amount!("color.change", lightness) if lightness
                ColorV.from_hsl(h, s, l, color.alpha)
              else
                ColorV.new(
                  red ? amount!("color.change", red, 0.0, 255.0) : color.red,
                  green ? amount!("color.change", green, 0.0, 255.0) : color.green,
                  blue ? amount!("color.change", blue, 0.0, 255.0) : color.blue,
                  color.alpha)
              end
            result = result.with_alpha(alpha!("color.change", alpha)) if alpha
            result
          end,
          "mix" => Fn.new do |args, kwargs|
            no_kwargs!("color.mix", kwargs)
            arity!("color.mix", args, 2, 3)
            weight = args.size == 3 ? amount!("color.mix", args[2]) : 50.0
            mix_colors(color!("color.mix", args[0]), color!("color.mix", args[1]), weight)
          end,
          "invert" => Fn.new do |args, kwargs|
            no_kwargs!("color.invert", kwargs)
            arity!("color.invert", args, 1, 2)
            color = color!("color.invert", args[0])
            weight = args.size == 2 ? amount!("color.invert", args[1]) : 100.0
            inverse = ColorV.new(255.0 - color.red, 255.0 - color.green,
              255.0 - color.blue, color.alpha)
            mix_colors(inverse, color, weight)
          end,
          "grayscale" => Fn.new do |args, kwargs|
            no_kwargs!("color.grayscale", kwargs)
            arity!("color.grayscale", args, 1)
            adjust_hsl(color!("color.grayscale", args[0]), saturation: -100.0)
          end,
          "complement" => Fn.new do |args, kwargs|
            no_kwargs!("color.complement", kwargs)
            arity!("color.complement", args, 1)
            adjust_hsl(color!("color.complement", args[0]), hue: 180.0)
          end,
          "adjust-hue" => Fn.new do |args, kwargs|
            no_kwargs!("color.adjust-hue", kwargs)
            arity!("adjust-hue", args, 2)
            color = color!("adjust-hue", args[0])
            adjust_hsl(color, hue: number!("adjust-hue", args[1]).value)
          end,
          "darken" => Fn.new do |args, kwargs|
            no_kwargs!("darken", kwargs)
            arity!("darken", args, 2)
            color = color!("darken", args[0])
            adjust_hsl(color, lightness: -amount!("darken", args[1]))
          end,
          "lighten" => Fn.new do |args, kwargs|
            no_kwargs!("lighten", kwargs)
            arity!("lighten", args, 2)
            color = color!("lighten", args[0])
            adjust_hsl(color, lightness: amount!("lighten", args[1]))
          end,
          "saturate" => Fn.new do |args, kwargs|
            no_kwargs!("saturate", kwargs)
            # One-argument `saturate(50%)` is the CSS filter, not this
            # function — leave it verbatim.
            arity!("saturate", args, 2)
            color = color!("saturate", args[0])
            adjust_hsl(color, saturation: amount!("saturate", args[1]))
          end,
          "desaturate" => Fn.new do |args, kwargs|
            no_kwargs!("desaturate", kwargs)
            arity!("desaturate", args, 2)
            color = color!("desaturate", args[0])
            adjust_hsl(color, saturation: -amount!("desaturate", args[1]))
          end,
          "opacify" => Fn.new do |args, kwargs|
            no_kwargs!("opacify", kwargs)
            arity!("opacify", args, 2)
            color = color!("opacify", args[0])
            color.with_alpha(color.alpha + alpha!("opacify", args[1]))
          end,
          "transparentize" => Fn.new do |args, kwargs|
            no_kwargs!("transparentize", kwargs)
            arity!("transparentize", args, 2)
            color = color!("transparentize", args[0])
            color.with_alpha(color.alpha - alpha!("transparentize", args[1]))
          end,
          "red" => Fn.new do |args, kwargs|
            no_kwargs!("color.red", kwargs)
            arity!("red", args, 1)
            Number.new(color!("red", args[0]).red8.to_f)
          end,
          "green" => Fn.new do |args, kwargs|
            no_kwargs!("color.green", kwargs)
            arity!("green", args, 1)
            Number.new(color!("green", args[0]).green8.to_f)
          end,
          "blue" => Fn.new do |args, kwargs|
            no_kwargs!("color.blue", kwargs)
            arity!("blue", args, 1)
            Number.new(color!("blue", args[0]).blue8.to_f)
          end,
          "hue" => Fn.new do |args, kwargs|
            no_kwargs!("color.hue", kwargs)
            arity!("hue", args, 1)
            Number.new(color!("hue", args[0]).hue, "deg")
          end,
          "saturation" => Fn.new do |args, kwargs|
            no_kwargs!("color.saturation", kwargs)
            arity!("saturation", args, 1)
            Number.new(color!("saturation", args[0]).saturation, "%")
          end,
          "lightness" => Fn.new do |args, kwargs|
            no_kwargs!("color.lightness", kwargs)
            arity!("lightness", args, 1)
            Number.new(color!("lightness", args[0]).lightness, "%")
          end,
          "alpha" => Fn.new do |args, kwargs|
            no_kwargs!("color.alpha", kwargs)
            arity!("alpha", args, 1)
            Number.new(color!("alpha", args[0]).alpha)
          end,
          "opacity" => Fn.new do |args, kwargs|
            no_kwargs!("color.opacity", kwargs)
            arity!("opacity", args, 1)
            Number.new(color!("opacity", args[0]).alpha)
          end,
        }

        # `rgba($color, $alpha)` / `rgb($color, $alpha)` — the Sass-only
        # two-argument spelling. Every other shape (`rgb(0, 0, 0)`,
        # `rgb(0 0 0 / 50%)`, relative color syntax) is real CSS and stays
        # verbatim, so this raises rather than reconstructing.
        RGBA_FN = Fn.new do |args, kwargs|
          no_kwargs!("rgba", kwargs)
          arity!("rgba", args, 2)
          color = color!("rgba", args[0])
          color.with_alpha(alpha!("rgba", args[1]))
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
