module Hwaro
  module Config
    module Options
      struct InitOptions
        property path : String
        property force : Bool

        def initialize(
          @path : String = ".",
          @force : Bool = false
        )
        end
      end
    end
  end
end
