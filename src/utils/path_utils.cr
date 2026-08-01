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
      # 3. Splits into segments and rejects traversal components
      # 4. Rejoins with "/" separator
      #
      # Example:
      #   sanitize_path("/foo/../bar//baz/") # => "foo/bar/baz"
      #   sanitize_path("%2Ffoo%2Fbar")      # => "foo/bar"
      #   sanitize_path("....//etc/passwd")  # => "etc/passwd"
      #   sanitize_path("notes/v1..v2")      # => "notes/v1..v2"
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

        # Split into segments and drop every one that can name a directory
        # OTHER than a child of the current one.
        #
        # The test is "is this segment nothing but dots and spaces", not "does
        # it contain ..". Only a segment that IS `.`/`..` traverses; one that
        # merely CONTAINS dots (`v1..v2`, `..foo`, `foo..`) is an ordinary
        # name, and discarding it silently RELOCATED whatever was being
        # addressed — a `content/a..b/` page collapsed to `""` and was written
        # over the site's `index.html`, destroying the homepage.
        #
        # Windows strips trailing dots and spaces from path components, so
        # `..`, `.. `, `. ` and `...` all normalize to `.` or `..` there.
        # Rejecting any all-dots-and-spaces segment therefore neutralizes MORE
        # traversal shapes than the old rule (which let `". "` through), while
        # keeping every previously-neutralized form neutralized: `..`,
        # `%2e%2e`, `%252e%252e`, `....//`, and the backslash variants all
        # still collapse away.
        parts = decoded.split(/[\/\\]/).reject { |seg| seg.empty? || seg.rstrip(". ").empty? }

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

      # File.match? that treats a malformed glob as non-matching instead of
      # raising File::BadPatternError, so a single config typo can't crash a
      # build or deploy.
      def glob_match?(pattern : String, path : String) : Bool
        File.match?(pattern, path)
      rescue File::BadPatternError
        false
      end
    end
  end
end
