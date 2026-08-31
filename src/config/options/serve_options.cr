module Hwaro
  module Config
    module Options
      struct ServeOptions
        # Where `hwaro serve` builds. A dedicated directory, NOT the
        # configured output_dir (issue #756): serve derives base_url from its
        # bind address, so its pages carry dev URLs (http://127.0.0.1:3000) —
        # sharing the output dir let a serve session silently poison a
        # previously deployable `hwaro build`, and hosting the leftover tree
        # leaked those dev links. Keep this directory out of version control
        # (alongside .hwaro_cache.json).
        DEV_OUTPUT_DIR = ".hwaro/serve"

        property host : String
        property port : Int32
        property base_url : String?
        property drafts : Bool
        property include_expired : Bool
        property include_future : Bool
        property minify : Bool
        # Concurrent render workers (0 = auto). See BuildOptions#workers.
        property workers : Int32
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
        property fast_start : Bool
        property fast_start_count : Int32
        # Custom response headers to inject during serve (from config.toml [serve.headers] + CLI --header)
        property headers : Hash(String, String)

        def initialize(
          @host : String = "127.0.0.1",
          @port : Int32 = 3000,
          @base_url : String? = nil,
          @drafts : Bool = false,
          @include_expired : Bool = false,
          @include_future : Bool = false,
          @minify : Bool = false,
          @workers : Int32 = 0,
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
          @fast_start : Bool = false,
          @fast_start_count : Int32 = 20,
          @headers : Hash(String, String) = {} of String => String,
        )
        end

        # Host as it must appear inside a URL. An IPv6 literal has to be
        # bracketed (RFC 3986) — without this `hwaro serve -b ::1` produced
        # `http://::1:3000`, which no browser can resolve, and baked that
        # string into every link, canonical and OG URL of the served site.
        def self.url_host(host : String) : String
          # `hwaro serve -b ""` (and any whitespace-only bind) is accepted by
          # the socket layer, but an empty host produces the authority-less
          # `http://:3000` — which then becomes the derived base_url and is
          # baked into every canonical, OG and feed URL of the previewed site.
          # "localhost", not a literal: an empty bind host is resolved by
          # `bind_tcp`, which lands on whichever loopback the resolver prefers
          # (`[::1]` on macOS), so a hard-coded 127.0.0.1 would point at an
          # address nothing is listening on. "localhost" follows the same
          # resolution the bind did.
          return "localhost" if host.blank?
          return host unless host.includes?(':')
          return host if host.starts_with?('[')
          # RFC 6874: a zone id's "%" separator must be percent-encoded inside
          # a URI, so `fe80::1%en0` becomes `[fe80::1%25en0]`. The lookahead
          # leaves an already-encoded host alone.
          "[#{host.sub(/%(?!25)/, "%25")}]"
        end

        # Convert to BuildOptions for initial build
        def to_build_options : BuildOptions
          # When no explicit --base-url is provided, derive from serve host:port
          # so that generated URLs reflect the actual server address
          effective_base_url = @base_url || "http://#{ServeOptions.url_host(@host)}:#{@port}"

          build = BuildOptions.new(
            output_dir: DEV_OUTPUT_DIR,
            base_url: effective_base_url,
            drafts: @drafts,
            include_expired: @include_expired,
            include_future: @include_future,
            minify: @minify,
            parallel: true,
            workers: @workers,
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
            fast_start: @fast_start,
            fast_start_count: @fast_start_count,
          )
          # Pin the dev output dir the same way an explicit `-o` is pinned:
          # `apply_build_config!` runs both in Server#run and inside
          # Builder#run on EVERY watch rebuild, and without this flag a
          # `[build] output_dir` in config.toml would pull serve right back
          # into the deployable tree this directory exists to protect.
          build.output_dir_explicit = true
          build
        end
      end
    end
  end
end
