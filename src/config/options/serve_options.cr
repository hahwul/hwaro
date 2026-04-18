module Hwaro
  module Config
    module Options
      struct ServeOptions
        property host : String
        property port : Int32
        property base_url : String?
        property drafts : Bool
        property include_expired : Bool
        property include_future : Bool
        property minify : Bool
        property open_browser : Bool
        property verbose : Bool
        property debug : Bool
        property access_log : Bool
        property error_overlay : Bool
        property live_reload : Bool
        property profile : Bool
        property cache_busting : Bool
        property env : String?
        property skip_og_image : Bool
        property skip_image_processing : Bool
        property cache : Bool
        property stream : Bool
        property memory_limit : String?
        property json : Bool

        def initialize(
          @host : String = "127.0.0.1",
          @port : Int32 = 3000,
          @base_url : String? = nil,
          @drafts : Bool = false,
          @include_expired : Bool = false,
          @include_future : Bool = false,
          @minify : Bool = false,
          @open_browser : Bool = false,
          @verbose : Bool = false,
          @debug : Bool = false,
          @access_log : Bool = false,
          @error_overlay : Bool = true,
          @live_reload : Bool = true,
          @profile : Bool = false,
          @cache_busting : Bool = true,
          @env : String? = nil,
          @skip_og_image : Bool = false,
          @skip_image_processing : Bool = false,
          @cache : Bool = false,
          @stream : Bool = false,
          @memory_limit : String? = nil,
          @json : Bool = false,
        )
        end

        # Convert to BuildOptions for initial build
        def to_build_options : BuildOptions
          # When no explicit --base-url is provided, derive from serve host:port
          # so that generated URLs reflect the actual server address
          effective_base_url = @base_url || "http://#{@host}:#{@port}"

          BuildOptions.new(
            output_dir: "public",
            base_url: effective_base_url,
            drafts: @drafts,
            include_expired: @include_expired,
            include_future: @include_future,
            minify: @minify,
            parallel: true,
            verbose: @verbose,
            profile: @profile,
            debug: @debug,
            error_overlay: @error_overlay,
            cache_busting: @cache_busting,
            cache: @cache,
            stream: @stream,
            memory_limit: @memory_limit,
            env: @env,
            skip_og_image: @skip_og_image,
            skip_image_processing: @skip_image_processing,
          )
        end
      end
    end
  end
end
