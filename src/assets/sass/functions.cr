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
# - Color functions — no color value model in the v2 subset.
#
# All argument mismatches raise SoftEvalError: lenient contexts fall back
# to verbatim CSS, strict contexts surface a located error.

require "./value"
require "./expr"

module Hwaro
  module Assets
    module Sass
      module Builtins
        alias Fn = Proc(Array(Value), Hash(String, Value), Value)

        # ---------------------------------------------------------------
        # Argument helpers
        # ---------------------------------------------------------------

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
            Number.new(n.value.round.to_f, n.unit)
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
            unit = same_units!("min", numbers)
            Number.new(numbers.min_of(&.value), unit)
          end,
          "max" => Fn.new do |args, kwargs|
            no_kwargs!("math.max", kwargs)
            arity!("max", args, 1, Int32::MAX)
            numbers = args.map { |a| number!("max", a) }
            unit = same_units!("max", numbers)
            Number.new(numbers.max_of(&.value), unit)
          end,
          "clamp" => Fn.new do |args, kwargs|
            no_kwargs!("math.clamp", kwargs)
            arity!("math.clamp", args, 3)
            numbers = args.map { |a| number!("math.clamp", a) }
            unit = same_units!("math.clamp", numbers)
            Number.new(numbers[1].value.clamp(numbers[0].value, numbers[2].value), unit)
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
            Str.new(s.text.upcase, quoted: s.quoted, quote_char: s.quote_char)
          end,
          "to-lower-case" => Fn.new do |args, kwargs|
            no_kwargs!("string.to-lower-case", kwargs)
            arity!("to-lower-case", args, 1)
            s = string!("to-lower-case", args[0])
            Str.new(s.text.downcase, quoted: s.quoted, quote_char: s.quote_char)
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
            sep = base.is_a?(ListV) ? base.sep : ListV::Sep::Space
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
              when Str    then "string"
              when BoolV  then "bool"
              when NullV  then "null"
              when ListV  then "list"
              when MapV   then "map"
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
          else             "string"
          end
        end

        def self.inspect_value(value : Value) : String
          case value
          when NullV
            "null"
          when ListV
            value.items.empty? ? "()" : value.to_css
          else
            value.to_css
          end
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
        }

        # `sass:<name>` module tables: {functions, variables}.
        MODULE_TABLES = {
          "math"   => {MATH_FNS, MATH_VARS},
          "string" => {STRING_FNS, {} of String => String},
          "list"   => {LIST_FNS, {} of String => String},
          "map"    => {MAP_FNS, {} of String => String},
          "meta"   => {META_FNS, {} of String => String},
        }
      end
    end
  end
end
