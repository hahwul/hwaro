# Content file publishing helper
#
# This processor-like module enables publishing non-Markdown files from `content/`
# into the build output while preserving their directory structure.
#
# Example:
#   content/about/profile.jpg -> /about/profile.jpg

require "../../models/config"

module Hwaro
  module Content
    module Processors
      module ContentFiles
        extend self

        # Returns true if the given content-relative file path should be published.
        def publish?(relative_path : String, config : Models::Config?) : Bool
          return false unless config
          config.content_files.publish?(relative_path)
        end
      end
    end
  end
end
