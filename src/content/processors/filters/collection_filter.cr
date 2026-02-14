require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module CollectionFilters
          def self.register(env : Crinja)
            # Array where filter
            env.filters["where"] = Crinja.filter({attribute: nil, value: nil}) do
              result = begin
                arr = target.as_a
                attr = arguments["attribute"].to_s
                val = arguments["value"]

                filtered = arr.select do |item|
                  begin
                    item_hash = item.as_h
                    item_val = item_hash[Crinja::Value.new(attr)]?
                    item_val == val
                  rescue
                    false
                  end
                end
                Crinja::Value.new(filtered)
              rescue
                Crinja::Value.new([] of Crinja::Value)
              end
              result
            end

            # Array sort_by filter
            env.filters["sort_by"] = Crinja.filter({attribute: nil, reverse: false}) do
              result = begin
                arr = target.as_a
                attr = arguments["attribute"].to_s
                reverse = arguments["reverse"].truthy?

                sorted = arr.sort_by do |item|
                  begin
                    item_hash = item.as_h
                    item_hash[Crinja::Value.new(attr)]?.try(&.to_s) || ""
                  rescue
                    ""
                  end
                end

                sorted = sorted.reverse if reverse
                Crinja::Value.new(sorted)
              rescue
                Crinja::Value.new([] of Crinja::Value)
              end
              result
            end

            # Group by filter
            env.filters["group_by"] = Crinja.filter({attribute: nil}) do
              result = begin
                arr = target.as_a
                attr = arguments["attribute"].to_s
                groups = {} of String => Array(Crinja::Value)

                arr.each do |item|
                  begin
                    item_hash = item.as_h
                    key = item_hash[Crinja::Value.new(attr)]?.try(&.to_s) || ""
                    groups[key] ||= [] of Crinja::Value
                    groups[key] << item
                  rescue
                    # Skip non-hash items
                  end
                end

                group_result = groups.map do |key, items|
                  {
                    "grouper" => Crinja::Value.new(key),
                    "list"    => Crinja::Value.new(items),
                  }
                end

                Crinja::Value.new(group_result.map { |h| Crinja::Value.new(h) })
              rescue
                Crinja::Value.new([] of Crinja::Value)
              end
              result
            end
          end
        end
      end
    end
  end
end
