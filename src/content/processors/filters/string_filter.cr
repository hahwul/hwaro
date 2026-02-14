require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module StringFilters
          def self.register(env : Crinja)
            # Truncate words filter
            env.filters["truncate_words"] = Crinja.filter({length: 50, end: "..."}) do
              text = target.to_s
              length = arguments["length"].as_number.to_i
              ending = arguments["end"].as_s

              words = text.split(/\s+/)
              if words.size > length
                words[0...length].join(" ") + ending
              else
                text
              end
            end

            # Slugify filter
            env.filters["slugify"] = Crinja.filter do
              text = target.to_s
              text.downcase
                .gsub(/[^\w\s-]/, "")
                .gsub(/[\s_-]+/, "-")
                .strip("-")
            end

            # Split filter
            env.filters["split"] = Crinja.filter({pat: ","}) do
              text = target.to_s
              separator = arguments["pat"].to_s
              parts = text.split(separator).map { |s| Crinja::Value.new(s.strip) }
              Crinja::Value.new(parts)
            end

            # Trim filter
            env.filters["trim"] = Crinja.filter do
              target.to_s.strip
            end
          end
        end
      end
    end
  end
end
