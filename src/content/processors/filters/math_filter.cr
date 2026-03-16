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
                num = target.as_number
                if num.is_a?(Float64)
                  if num.nan? || num.infinite? || num > Int64::MAX.to_f || num < Int64::MIN.to_f
                    target
                  else
                    Crinja::Value.new(num.ceil.to_i64)
                  end
                else
                  Crinja::Value.new(num.to_i64)
                end
              rescue
                target
              end
            end

            # Floor filter — rounds down to the nearest integer
            env.filters["floor"] = Crinja.filter do
              begin
                num = target.as_number
                if num.is_a?(Float64)
                  if num.nan? || num.infinite? || num > Int64::MAX.to_f || num < Int64::MIN.to_f
                    target
                  else
                    Crinja::Value.new(num.floor.to_i64)
                  end
                else
                  Crinja::Value.new(num.to_i64)
                end
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
