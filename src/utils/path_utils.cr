require "uri"

module Hwaro
  module Utils
    module PathUtils
      extend self

      # Sanitize path to prevent directory traversal and normalize separators
      #
      # This method performs the following operations:
      # 1. URL-decodes the path
      # 2. Removes ".." sequences (prevent traversal)
      # 3. Removes null bytes
      # 4. Normalizes multiple slashes to single slash
      # 5. Strips leading and trailing slashes
      #
      # Example:
      #   sanitize_path("/foo/../bar//baz/") # => "foo/bar/baz"
      #   sanitize_path("%2Ffoo%2Fbar")      # => "foo/bar"
      def sanitize_path(path : String) : String
        # URL-decode the path first to handle encoded traversal attempts
        decoded = URI.decode(path)

        # Remove any parent directory references, null bytes, and normalize slashes
        decoded
          .gsub("..", "") # Remove parent directory references
          .gsub("\0", "") # Remove null bytes
          .squeeze("/")   # Normalize multiple slashes
          .strip("/")     # Strip leading/trailing slashes
      end
    end
  end
end
