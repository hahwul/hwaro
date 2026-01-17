module Hwaro
  module Options
    struct BuildOptions
      property output_dir : String
      property drafts : Bool
      property minify : Bool
      property parallel : Bool

      def initialize(
        @output_dir : String = "public",
        @drafts : Bool = false,
        @minify : Bool = false,
        @parallel : Bool = true
      )
      end
    end
  end
end
