module Hwaro
  module Config
    module Options
      struct ImportOptions
        property source_type : String
        property path : String
        property output_dir : String
        property drafts : Bool
        property verbose : Bool
        property force : Bool

        def initialize(
          @source_type : String = "",
          @path : String = "",
          @output_dir : String = "content",
          @drafts : Bool = false,
          @verbose : Bool = false,
          @force : Bool = false,
        )
        end
      end
    end
  end
end
