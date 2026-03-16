module Hwaro
  module Config
    module Options
      struct BuildOptions
        property output_dir : String
        property base_url : String?
        property drafts : Bool
        property include_expired : Bool
        property minify : Bool
        property parallel : Bool
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

        def initialize(
          @output_dir : String = "public",
          @base_url : String? = nil,
          @drafts : Bool = false,
          @include_expired : Bool = false,
          @minify : Bool = false,
          @parallel : Bool = true,
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
          case value.strip
          when /^(\d+(?:\.\d+)?)\s*[Gg]$/
            ($1.to_f * 1024 * 1024 * 1024).to_i64
          when /^(\d+(?:\.\d+)?)\s*[Mm]$/
            ($1.to_f * 1024 * 1024).to_i64
          when /^(\d+(?:\.\d+)?)\s*[Kk]$/
            ($1.to_f * 1024).to_i64
          when /^(\d+)$/
            $1.to_i64
          else
            raise "Invalid memory limit format: #{value}. Use format like '2G', '512M', or '256K'."
          end
        end
      end
    end
  end
end
