module Hwaro
  module Config
    module Options
      struct InitOptions
        property path : String
        property force : Bool
        property skip_agents_md : Bool
        property skip_sample_content : Bool

        def initialize(
          @path : String = ".",
          @force : Bool = false,
          @skip_agents_md : Bool = false,
          @skip_sample_content : Bool = false,
        )
        end
      end
    end
  end
end
