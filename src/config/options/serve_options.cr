module Hwaro
  module Config
    module Options
      struct ServeOptions
        property host : String
        property port : Int32
        property base_url : String?
        property drafts : Bool
        property minify : Bool
        property open_browser : Bool
        property verbose : Bool
        property debug : Bool
        property access_log : Bool
        property error_overlay : Bool
        property live_reload : Bool
        property profile : Bool
        property cache_busting : Bool

        def initialize(
          @host : String = "0.0.0.0",
          @port : Int32 = 3000,
          @base_url : String? = nil,
          @drafts : Bool = false,
          @minify : Bool = false,
          @open_browser : Bool = false,
          @verbose : Bool = false,
          @debug : Bool = false,
          @access_log : Bool = false,
          @error_overlay : Bool = true,
          @live_reload : Bool = false,
          @profile : Bool = false,
          @cache_busting : Bool = true,
        )
        end

        # Convert to BuildOptions for initial build
        def to_build_options : BuildOptions
          BuildOptions.new(
            output_dir: "public",
            base_url: @base_url,
            drafts: @drafts,
            minify: @minify,
            parallel: true,
            verbose: @verbose,
            profile: @profile,
            debug: @debug,
            error_overlay: @error_overlay,
            cache_busting: @cache_busting,
            stream: false,
            memory_limit: nil,
          )
        end
      end
    end
  end
end
