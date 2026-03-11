require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module MathFilters
          def self.register(env : Crinja)
            # Ceil filter — rounds up to the nearest integer
            env.filters["ceil"] = Crinja.filter do
              begin
                Crinja::Value.new(target.as_number.ceil.to_i64)
              rescue
                target
              end
            end

            # Floor filter — rounds down to the nearest integer
            env.filters["floor"] = Crinja.filter do
              begin
                Crinja::Value.new(target.as_number.floor.to_i64)
              rescue
                target
              end
            end
          end
        end
      end
    end
  end
end
