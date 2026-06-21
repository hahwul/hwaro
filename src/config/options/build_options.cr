module Hwaro
  module Config
    module Options
      struct BuildOptions
        property output_dir : String
        property base_url : String?
        property drafts : Bool
        property include_expired : Bool
        property include_future : Bool
        property minify : Bool
        property parallel : Bool
        # Number of concurrent render workers (fibers) for the parallel render
        # phase. 0 = auto (CPU-based, the default). Lowering it (e.g. `--jobs 2`)
        # reduces effective render parallelism, which on template/Crinja-heavy
        # sites is often FASTER: those pages allocate many small objects, and
        # past ~2 workers Boehm's global allocation lock contends harder than
        # the extra cores help. Markdown-heavy sites keep scaling, so the
        # default stays auto. Never changes output — only render concurrency.
        property workers : Int32
        property cache : Bool
        property full : Bool
        property highlight : Bool
        property verbose : Bool
        property profile : Bool
        property debug : Bool
        property error_overlay : Bool
        property cache_busting : Bool
        property stream : Bool
        property memory_limit : String?
        property env : String?
        property skip_og_image : Bool
        property skip_image_processing : Bool
        # Keep existing output files between rebuilds. Used by `hwaro serve`'s
        # watch-triggered rebuilds so repeated full rebuilds don't wipe the
        # already-processed resized images (see `ImageHooks#process_images`
        # mtime-skip logic, which only works when destinations survive).
        property preserve_output : Bool
        # When set (dev-server only), render only the homepage + the N most
        # recent pages on the initial pass; the remaining pages are stashed
        # on the Builder and rendered by a background fiber after the server
        # is already serving. Drops "ready" time on large sites from O(all)
        # to O(N). Always paired with `fast_start_count`.
        property fast_start : Bool
        property fast_start_count : Int32

        # True when this build is being run as part of `hwaro serve` (dev server).
        # Hooks can use this to change behavior (e.g. lazy OG generation).
        property serve_mode : Bool = false

        def initialize(
          @output_dir : String = "public",
          @base_url : String? = nil,
          @drafts : Bool = false,
          @include_expired : Bool = false,
          @include_future : Bool = false,
          @minify : Bool = false,
          @parallel : Bool = true,
          @workers : Int32 = 0,
          @cache : Bool = false,
          @full : Bool = false,
          @highlight : Bool = true,
          @verbose : Bool = false,
          @profile : Bool = false,
          @debug : Bool = false,
          @error_overlay : Bool = false,
          @cache_busting : Bool = true,
          @stream : Bool = false,
          @memory_limit : String? = nil,
          @env : String? = nil,
          @skip_og_image : Bool = false,
          @skip_image_processing : Bool = false,
          @preserve_output : Bool = false,
          @fast_start : Bool = false,
          @fast_start_count : Int32 = 20,
          @serve_mode : Bool = false,
        )
        end

        def streaming? : Bool
          @stream || !@memory_limit.nil?
        end

        def batch_size : Int32
          if limit = @memory_limit
            bytes = parse_memory_limit(limit)
            # Heuristic: ~50KB per page
            size = bytes // (50_i64 * 1024)
            size = size.clamp(1, Int32::MAX.to_i64).to_i32
            size
          else
            # Default batch size: 500 pages.  The previous default of 50 caused
            # excessive GC.collect + cache clear cycles on large sites (e.g.
            # 5000 pages → 100 batches → 100 GC cycles).  500 reduces this to
            # 10 cycles while still bounding peak memory for very large sites.
            500
          end
        end

        private def parse_memory_limit(value : String) : Int64
          bytes =
            case value.strip
            when /^(\d+(?:\.\d+)?)\s*[Gg]$/
              $1.to_f * 1024 * 1024 * 1024
            when /^(\d+(?:\.\d+)?)\s*[Mm]$/
              $1.to_f * 1024 * 1024
            when /^(\d+(?:\.\d+)?)\s*[Kk]$/
              $1.to_f * 1024
            when /^(\d+)$/
              $1.to_f
            else
              raise "Invalid memory limit format: #{value}. Use format like '2G', '512M', or '256K'."
            end

          # Validate the resolved size before narrowing to Int64 so callers get a
          # clear message instead of a degenerate batch size (0 -> batch of 1) or
          # a raw "Arithmetic overflow" from `.to_i64` on an enormous value.
          if bytes < 1
            raise "Invalid memory limit: #{value}. Must be a positive size like '2G', '512M', or '256K'."
          elsif bytes >= Int64::MAX.to_f
            raise "Memory limit too large: #{value}. Maximum is #{Int64::MAX} bytes (~8 EiB)."
          end

          bytes.to_i64
        end
      end
    end
  end
end
