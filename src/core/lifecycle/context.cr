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

        # Content
        property pages : Array(Models::Page)
        property sections : Array(Models::Section)

        # Raw files (JSON, XML, etc.)
        property raw_files : Array(RawFile)

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

        def initialize(@options : Config::Options::BuildOptions)
          @pages = [] of Models::Page
          @sections = [] of Models::Section
          @raw_files = [] of RawFile
          @templates = {} of String => String
          @output_dir = options.output_dir
          @metadata = {} of String => String | Bool | Int32 | Float64
          @stats = BuildStats.new
        end

        # Convenience: all pages including sections
        def all_pages : Array(Models::Page)
          (@pages + @sections).as(Array(Models::Page))
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
          @metadata[key]?.try(&.as?(Bool)) || default
        end

        def get_int(key : String, default : Int32 = 0) : Int32
          @metadata[key]?.try(&.as?(Int32)) || default
        end
      end

      # Build statistics tracking
      struct BuildStats
        property pages_read : Int32
        property pages_rendered : Int32
        property pages_skipped : Int32
        property files_written : Int32
        property cache_hits : Int32
        property raw_files_processed : Int32
        property start_time : Time::Instant?
        property end_time : Time::Instant?

        def initialize
          @pages_read = 0
          @pages_rendered = 0
          @pages_skipped = 0
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
