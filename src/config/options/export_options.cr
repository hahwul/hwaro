module Hwaro
  module Config
    module Options
      struct ExportOptions
        property target_type : String
        property output_dir : String
        property content_dir : String
        property drafts : Bool
        property verbose : Bool

        def initialize(
          @target_type : String = "",
          @output_dir : String = "export",
          @content_dir : String = "content",
          @drafts : Bool = false,
          @verbose : Bool = false,
        )
        end
      end
    end
  end
end
