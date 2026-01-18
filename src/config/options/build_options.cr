module Hwaro
  module Config
    module Options
      struct BuildOptions
        property output_dir : String
        property drafts : Bool
        property minify : Bool
        property parallel : Bool
        property cache : Bool

        def initialize(
          @output_dir : String = "public",
          @drafts : Bool = false,
          @minify : Bool = false,
          @parallel : Bool = true,
          @cache : Bool = false,
        )
        end
      end
    end
  end
end
