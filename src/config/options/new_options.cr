module Hwaro
  module Config
    module Options
      class NewOptions
        property path : String?
        property title : String?
        property archetype : String?

        def initialize(@path : String? = nil, @title : String? = nil, @archetype : String? = nil)
        end
      end
    end
  end
end
