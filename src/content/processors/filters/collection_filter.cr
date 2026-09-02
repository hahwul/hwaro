require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module CollectionFilters
          def self.register(env : Crinja)
            # Array where filter
            env.filters["where"] = Crinja.filter({attribute: nil, value: nil}) do
              safe_array do
                arr = target.as_a
                attr_key = Crinja::Value.new(arguments["attribute"].to_s)
                val = arguments["value"]

                arr.select do |item|
                  item_hash = item.as_h
                  item_val = item_hash[attr_key]?
                  item_val == val
                rescue Exception
                  false
                end
              end
            end

            # Array sort_by filter
            env.filters["sort_by"] = Crinja.filter({attribute: nil, reverse: false}) do
              safe_array do
                arr = target.as_a
                attr_key = Crinja::Value.new(arguments["attribute"].to_s)
                reverse = arguments["reverse"].truthy?

                # Compare values directly so numeric attributes (weight,
                # word_count, numeric extra) sort numerically instead of
                # lexicographically ("1","10","2"). Strings/dates fall back to
                # string comparison; a missing attribute sorts as "".
                sorted = arr.sort do |a, b|
                  av = a.as_h[attr_key]? || Crinja::Value.new("")
                  bv = b.as_h[attr_key]? || Crinja::Value.new("")
                  cmp = if av.number? && bv.number?
                          av.as_number <=> bv.as_number
                        else
                          av.to_s <=> bv.to_s
                        end
                  cmp || 0
                rescue Exception
                  0
                end

                sorted = sorted.reverse if reverse
                sorted
              end
            end

            # Group by filter
            env.filters["group_by"] = Crinja.filter({attribute: nil}) do
              safe_array do
                arr = target.as_a
                attr_key = Crinja::Value.new(arguments["attribute"].to_s)
                groups = {} of String => Array(Crinja::Value)

                arr.each do |item|
                  item_hash = item.as_h
                  key = item_hash[attr_key]?.try(&.to_s) || ""
                  groups[key] ||= [] of Crinja::Value
                  groups[key] << item
                rescue Exception
                  # Skip non-hash items
                end

                group_result = groups.map do |key, items|
                  {
                    "grouper" => Crinja::Value.new(key),
                    "list"    => Crinja::Value.new(items),
                  }
                end

                group_result.map { |h| Crinja::Value.new(h) }
              end
            end

            # Unique filter — removes duplicate values from an array
            env.filters["unique"] = Crinja.filter do
              safe_array do
                arr = target.as_a
                seen = Set(String).new
                arr.select do |item|
                  key = item.to_s
                  if seen.includes?(key)
                    false
                  else
                    seen << key
                    true
                  end
                end
              end
            end

            # Flatten filter — flattens nested arrays one level
            env.filters["flatten"] = Crinja.filter do
              safe_array do
                arr = target.as_a
                flattened = [] of Crinja::Value
                arr.each do |item|
                  sub = item.as_a
                  sub.each { |v| flattened << v }
                rescue Exception
                  flattened << item
                end
                flattened
              end
            end

            # `first` / `last` — override Crinja's built-ins, which call
            # `Enumerable#first` / `Indexable#last` on the raw value and let
            # the resulting Crystal exception escape. On an EMPTY sequence
            # that aborted the whole build with a bare `Empty enumerable` /
            # `Index out of bounds` and no template file:line, because those
            # are plain Crystal errors rather than `Crinja::Error`s (see
            # TemplateEngine#render). An empty section/collection is ordinary
            # site state — `{{ section.pages | first }}` on a section with no
            # pages must not be fatal. Jinja2 yields `Undefined` there (which
            # renders as "" and is falsy), so do the same; every non-empty
            # input still goes through the upstream code path unchanged, and a
            # non-sequence target still raises Crinja's located `TypeError`.
            #
            # A FRESH Undefined each time, never the shared `Value::UNDEFINED`
            # singleton: the evaluator renames an Undefined in place when it
            # is stored under a new name (`{% set d = {'a': ([] | first)} %}`
            # writes `d.a` into it), so handing out the singleton let one
            # page's variable name leak into another page's error message —
            # and race across render workers.
            env.filters["first"] = Crinja.filter do
              CollectionFilters.empty_sequence?(target) ? Crinja::Value.new(Crinja::Undefined.new) : target.first.raw
            end

            env.filters["last"] = Crinja.filter do
              CollectionFilters.empty_sequence?(target) ? Crinja::Value.new(Crinja::Undefined.new) : target.last.raw
            end

            # Compact filter — removes nil/empty values from an array
            env.filters["compact"] = Crinja.filter do
              safe_array do
                arr = target.as_a
                arr.reject do |item|
                  item.raw.nil? || item.to_s.empty?
                end
              end
            end
          end

          # True when `value` is a sequence with no elements — the case
          # upstream `first`/`last` crash on. Deliberately narrow: anything
          # that is not a string/hash/indexable (an Int, say) reports `false`
          # so the upstream filter still raises its located `TypeError`.
          # An Undefined counts as empty: Jinja2 iterates it as nothing, and
          # `{{ get_section(path='nope').pages | first }}` or a missing
          # `page.extra.images | first` is the same "ordinary site state" an
          # empty section is — Crinja's own `raw_each` already treats it so.
          def self.empty_sequence?(value : Crinja::Value) : Bool
            case raw = value.raw
            when Crinja::Undefined  then true
            when String             then raw.empty?
            when Crinja::SafeString then raw.to_s.empty?
            when Hash               then raw.empty?
            when Indexable          then raw.empty?
            else                         false
            end
          end

          # Wrap a filter body that builds an Array(Crinja::Value): return it as
          # a Crinja::Value, falling back to an empty array on any error.
          private def self.safe_array(& : -> Array(Crinja::Value)) : Crinja::Value
            Crinja::Value.new(yield)
          rescue Exception
            Crinja::Value.new([] of Crinja::Value)
          end
        end
      end
    end
  end
end
