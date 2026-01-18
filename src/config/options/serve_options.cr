module Hwaro
  module Config
    module Options
      struct ServeOptions
        property host : String
        property port : Int32
        property drafts : Bool
        property open_browser : Bool

        def initialize(
          @host : String = "0.0.0.0",
          @port : Int32 = 3000,
          @drafts : Bool = false,
          @open_browser : Bool = false
        )
        end

        # Convert to BuildOptions for initial build
        def to_build_options : BuildOptions
          BuildOptions.new(
            output_dir: "public",
            drafts: @drafts,
            minify: false,
            parallel: true
          )
        end
      end
    end
  end
end
