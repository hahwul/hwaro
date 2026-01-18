module Hwaro
  module Config
    module Options
      class NewOptions
        property path : String?
        property title : String?

        def initialize(@path : String? = nil, @title : String? = nil)
        end
      end
    end
  end
end
