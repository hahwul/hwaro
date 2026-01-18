# Backward compatibility wrapper for Build module
# The main implementation has moved to core/build/builder.cr

require "./build/builder"
require "./build/cache"
require "./build/parallel"

module Hwaro
  module Core
    # Backward compatibility: Build class wraps the new Builder
    class Build
      def initialize
        @builder = Build::Builder.new
      end

      def run(options : Options::BuildOptions)
        @builder.run(options)
      end

      def run(output_dir : String = "public", drafts : Bool = false, minify : Bool = false, parallel : Bool = true)
        @builder.run(
          output_dir: output_dir,
          drafts: drafts,
          minify: minify,
          parallel: parallel,
          cache: false
        )
      end

      @builder : Build::Builder
    end
  end
end
