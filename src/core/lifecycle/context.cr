# Build context - shared state across the build lifecycle
#
# The BuildContext carries all state needed during the build process
# and is passed to every hook handler.

require "../../models/site"
require "../../models/page"
require "../../models/config"
require "../../config/options/build_options"

module Hwaro
  module Core
    module Lifecycle
      # Represents a raw file (JSON, XML, etc.) that needs processing
      struct RawFile
        property source_path : String
        property relative_path : String
        property extension : String

        def initialize(@source_path : String, @relative_path : String)
          @extension = File.extname(@source_path).downcase
        end
      end

      # Build context that flows through all phases
      class BuildContext
        # Build options
        property options : Config::Options::BuildOptions

        # Site data
        property site : Models::Site?
        property config : Models::Config?

        # Content (use setter to auto-invalidate all_pages cache)
        getter pages : Array(Models::Page)
        getter sections : Array(Models::Section)

        # Raw files (JSON, XML, etc.)
        property raw_files : Array(RawFile)

        # Sections removed by early draft/expired/future filtering (e.g. the
        # MarkdownHooks AfterReadContent filter) whose [cascade] must still
        # reach their descendants. apply_cascades merges these with the
        # surviving sections when building the cascade map.
        property excluded_cascade_sections : Array(Models::Section)

        # Templates
        property templates : Hash(String, String)

        # Output
        property output_dir : String

        # Cache reference
        property cache : Build::Cache?

        # Phase-specific metadata for inter-hook communication
        property metadata : Hash(String, String | Bool | Int32 | Float64)

        # Track build statistics
        property stats : BuildStats

        # When `--fast-start` is active, this is populated with the subset of
        # pages the initial pass should process (homepage + recent N + section
        # indexes). BeforeRender hooks (OG image, image resize) consult this to
        # skip work for the deferred subset; the background render pass clears
        # it and re-runs those hooks for the rest. Nil outside of fast-start.
        property priority_pages : Array(Models::Page)?

        # True when the current run only handles a subset of the site's
        # pages — set on both passes of a `--fast-start` session
        # (priority + deferred). Hooks that persist per-page state
        # (e.g. the OG image manifest) use this to skip the "truncate
        # entries for missing pages" prune, so the second pass doesn't
        # wipe the first pass's writes.
        property partial_render : Bool = false

        # Profiler reference (only set when --profile is active).
        # Allows expensive hooks (OG image, image resize) to record their
        # own timing so the true cost distribution inside the Render phase
        # becomes visible.
        property profiler : Hwaro::Profiler?

        @all_pages_cache : Array(Models::Page)?

        def initialize(@options : Config::Options::BuildOptions)
          @pages = [] of Models::Page
          @sections = [] of Models::Section
          @raw_files = [] of RawFile
          @excluded_cascade_sections = [] of Models::Section
          @templates = {} of String => String
          @output_dir = options.output_dir
          @metadata = {} of String => String | Bool | Int32 | Float64
          @stats = BuildStats.new
        end

        # Setters that auto-invalidate cache
        def pages=(value : Array(Models::Page))
          @pages = value
          @all_pages_cache = nil
        end

        def sections=(value : Array(Models::Section))
          @sections = value
          @all_pages_cache = nil
        end

        # Convenience: all pages including sections (cached after first call)
        def all_pages : Array(Models::Page)
          @all_pages_cache ||= (@pages + @sections).as(Array(Models::Page))
        end

        # Invalidate the cached all_pages array (call after modifying pages/sections)
        def invalidate_all_pages_cache
          @all_pages_cache = nil
        end

        # Set metadata with type safety
        def set(key : String, value : String | Bool | Int32 | Float64)
          @metadata[key] = value
        end

        # Get metadata with default
        def get_string(key : String, default : String = "") : String
          @metadata[key]?.try(&.as?(String)) || default
        end

        def get_bool(key : String, default : Bool = false) : Bool
          # NOTE: `value || default` is wrong here — a legitimately stored
          # `false` is falsy and would collapse to `default`, inverting the
          # flag a previous hook set. Distinguish "absent / wrong type" (nil)
          # from a stored `false`.
          val = @metadata[key]?.try(&.as?(Bool))
          val.nil? ? default : val
        end

        def get_int(key : String, default : Int32 = 0) : Int32
          # Same nil-vs-stored-value distinction as get_bool. `0 || default`
          # happens to work (0 is truthy in Crystal) but the explicit form
          # keeps the two getters consistent and intent-revealing.
          val = @metadata[key]?.try(&.as?(Int32))
          val.nil? ? default : val
        end
      end

      # Build statistics tracking
      struct BuildStats
        property pages_read : Int32
        property pages_rendered : Int32
        property pages_skipped : Int32
        property pages_failed : Int32
        property files_written : Int32
        property cache_hits : Int32
        property raw_files_processed : Int32
        property start_time : Time::Instant?
        property end_time : Time::Instant?

        def initialize
          @pages_read = 0
          @pages_rendered = 0
          @pages_skipped = 0
          @pages_failed = 0
          @files_written = 0
          @cache_hits = 0
          @raw_files_processed = 0
        end

        def elapsed : Float64
          if st = @start_time
            if et = @end_time
              (et - st).total_milliseconds
            else
              (Time.instant - st).total_milliseconds
            end
          else
            0.0
          end
        end
      end
    end
  end
end
