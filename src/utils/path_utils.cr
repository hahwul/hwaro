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
        split_safe_segments(path)[0].join("/")
      end

      # ONE traversal predicate, TWO policies.
      #
      # Returns the safe segments of `path`, plus whether any segment had to be
      # refused because it could name something other than a child of the
      # directory it appears in. Callers pick a policy:
      #
      #   * neutralize-and-continue (`sanitize_path`) — for untrusted input
      #     that must still yield a usable path: importer section names,
      #     remote-scaffold archive entries.
      #   * refuse-outright (the build's `url_output_path`) — for writers,
      #     where dropping a segment does not sanitize anything, it RELOCATES
      #     the page onto whatever already occupies the shortened path. That is
      #     how `content/a..b/` came to overwrite the site's `index.html`.
      #
      # Both policies share this body deliberately. They were hand-copied
      # before and drifted, which is precisely how one build writer
      # (`generate_redirect_page`) kept the wrong policy and clobbered the
      # homepage while its sibling refused the same URL.
      #
      # A segment is refused when it is nothing but dots and ASCII spaces.
      # Windows' `RtlDosPathNameToNtPathName` trims trailing `.` and ASCII
      # space and nothing else, so `..`, `.. `, `. ` and `...` all name `.`
      # or `..` there. Segments that merely CONTAIN dots (`v1..v2`, `..foo`)
      # are ordinary names and are kept.
      #
      # This is not identical to the pre-2026-08 rule, which refused any
      # segment containing `..`. Newly KEPT are segments that contain `..` but
      # cannot traverse on any supported platform — `a..b`, and the
      # whitespace-suffixed forms `"..\t"`, `"..\u00a0"` (only ASCII space
      # and `.` are trimmed by Win32, so these stay distinct filenames).
      # Newly REFUSED are all-space segments such as `"   "`, which the old
      # rule let through.
      def split_safe_segments(path : String) : {Array(String), Bool}
        # Fast path — no percent-encoding, no NUL, no backslash: the decode
        # loop and NUL-strip are identity and the split needs no regex.
        # This runs several times per page on every output-path computation.
        # (A backslash can also arrive percent-encoded, but that input
        # contains '%' and takes the slow path.)
        unless path.includes?('%') || path.includes?('\u0000') || path.includes?('\\')
          return collect_safe_segments(path.split('/'))
        end

        # Decode repeatedly so percent-encoded traversal (`%2e%2e`,
        # `%252e%252e`) is judged in its decoded form.
        decoded = path
        loop do
          next_decoded = URI.decode(decoded)
          break if next_decoded == decoded
          decoded = next_decoded
        end
        decoded = decoded.gsub("\u0000", "")

        collect_safe_segments(decoded.split(/[\/\\]/))
      end

      private def collect_safe_segments(parts : Array(String)) : {Array(String), Bool}
        segments = [] of String
        refused = false
        parts.each do |segment|
          next if segment.empty?
          if segment.rstrip(". ").empty?
            refused = true
            next
          end
          segments << segment
        end
        {segments, refused}
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
