require "uri"

module Hwaro
  module Utils
    module PathUtils
      extend self

      # Sanitize path to prevent directory traversal and normalize separators
      #
      # This method performs the following operations:
      # 1. URL-decodes the path (repeated until stable to catch double-encoding)
      # 2. Removes null bytes
      # 3. Splits into segments and rejects ".." components
      # 4. Rejoins with "/" separator
      #
      # Example:
      #   sanitize_path("/foo/../bar//baz/") # => "foo/bar/baz"
      #   sanitize_path("%2Ffoo%2Fbar")      # => "foo/bar"
      #   sanitize_path("....//etc/passwd")  # => "etc/passwd"
      def sanitize_path(path : String) : String
        # URL-decode repeatedly until stable to catch double/triple encoding
        decoded = path
        loop do
          next_decoded = URI.decode(decoded)
          break if next_decoded == decoded
          decoded = next_decoded
        end

        # Remove null bytes
        decoded = decoded.gsub("\0", "")

        # Split into segments, reject any that are empty, ".", "..",
        # or contain ".." anywhere (e.g. "....") to prevent bypass attempts
        parts = decoded.split(/[\/\\]/).reject { |seg| seg.empty? || seg == "." || seg.includes?("..") }

        parts.join("/")
      end

      # True when `path`, with all symbolic links resolved, lies inside
      # `root` (also fully resolved). Used to stop symlinked source files
      # from publishing content that lives outside the project — e.g. a
      # `static/leak -> ~/.ssh/id_rsa` symlink would otherwise be copied
      # into the public output. In-repo symlinks resolve back within the
      # root and are kept. Returns false on a dangling/unreadable path
      # rather than raising.
      def resolves_within?(path : String, root : String) : Bool
        real_path = begin
          File.realpath(path)
        rescue File::Error
          return false
        end
        real_root = begin
          File.realpath(root)
        rescue File::Error
          return false
        end
        real_path == real_root || real_path.starts_with?(real_root + File::SEPARATOR)
      end
    end
  end
end
