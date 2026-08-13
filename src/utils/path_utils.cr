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
        split_safe_segments(normalize_separators(path))[0].join("/")
      end

      # Fold every separator spelling this input might carry — percent-encoded
      # (`%2f`, `%252f`) and Windows' `\` — into a real `/` BEFORE the segment
      # split.
      #
      # Only the neutralize policy does this, and only because its inputs
      # legitimately arrive that way: a Windows-authored archive entry names
      # `content\posts\a.md`, and refusing the entry outright instead of
      # normalizing it would silently drop a scaffold file. The refuse-outright
      # policy must NOT normalize — see `split_safe_segments` for why turning a
      # hidden separator into a real one is data loss for a writer.
      private def normalize_separators(path : String) : String
        return path unless path.includes?('%') || path.includes?('\\')
        decode_until_stable(path).scrub.tr("\\", "/")
      end

      # Percent-decode until the result stops changing, so double- and
      # triple-encoded input (`%252e%252e`) is judged in its final decoded
      # form. Every pass either shortens the string or leaves it untouched, so
      # this cannot spin.
      private def decode_until_stable(value : String) : String
        decoded = value
        loop do
          next_decoded = URI.decode(decoded)
          break if next_decoded == decoded
          decoded = next_decoded
        end
        decoded
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
      #
      # A segment is ALSO refused when decoding it reveals a separator, and the
      # split therefore happens BEFORE the decode. Decoding the whole path
      # first turned `%2f` into a real separator: the content file
      # `posts/a%2fb.md` claims the URL `/posts/a%2fb/` but resolved to the
      # output path `posts/a/b/index.html` and overwrote the page that
      # legitimately owns it — the build reported "render: 2 pages", left one
      # file on disk, and said nothing. A literal `\` is refused for the same
      # reason from the other side: it separates on Windows, and browsers
      # normalize it to `/` inside a URL path, so a segment holding one can
      # never be both published and linked to correctly everywhere. Refusing
      # is the only honest answer for a name whose depth is ambiguous;
      # resolving it either way silently destroys somebody's page.
      def split_safe_segments(path : String) : {Array(String), Bool}
        # Fast path — no percent-encoding, no NUL, no backslash: the decode
        # loop and NUL-strip are identity and no segment can be hiding a
        # separator behind an escape.
        # This runs several times per page on every output-path computation.
        # (A backslash can also arrive percent-encoded, but that input
        # contains '%' and takes the slow path.)
        unless path.includes?('%') || path.includes?('\u0000') || path.includes?('\\')
          return collect_safe_segments(path.split('/'))
        end

        decoded_parts = [] of String
        separator_refused = false

        path.split('/').each do |raw|
          next if raw.empty?

          # Decode repeatedly so percent-encoded traversal (`%2e%2e`,
          # `%252e%252e`) is judged in its decoded form — but one segment at a
          # time, so a separator that only appears after decoding stays inside
          # the segment it came from instead of becoming a directory level.
          decoded = decode_until_stable(raw)
          decoded = decoded.gsub("\u0000", "")

          # A percent-encoded overlong sequence (`%C0%AE`) decodes to invalid
          # UTF-8, and PCRE2 raises on it — letting a hostile archive entry or
          # importer path crash the CLI. Neutralize invalid bytes instead
          # (scrub is a no-op for valid UTF-8); overlong ".." is not ".." to
          # any filesystem, so this loses no traversal protection.
          decoded = decoded.scrub

          if decoded.includes?('/') || decoded.includes?('\\')
            separator_refused = true
            next
          end

          decoded_parts << decoded
        end

        # The dots-and-spaces predicate stays in ONE place for both paths —
        # see the note above about hand-copied policies drifting.
        segments, dots_refused = collect_safe_segments(decoded_parts)
        {segments, separator_refused || dots_refused}
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

      # The output FILE a site-relative URL will be written to, normalized so
      # that two different URL strings landing on one file share a key.
      # `nil` when the URL cannot be published at all (a refused segment) —
      # the writer reports those through its own warn-and-skip path.
      #
      # The Render phase's collision detector used to key on the raw URL
      # string, so `/posts/a/b/` and `/posts/a%2fb/` looked like two separate
      # outputs while being one `posts/a/b/index.html`: the build claimed
      # "render: 2 pages", wrote one file, and never mentioned the page it
      # destroyed.
      def output_file_key(url : String) : String?
        segments, refused = split_safe_segments(url.lchop("/"))
        return if refused
        segments.join("/")
      end

      # Case- and Unicode-folded form of an `output_file_key`. APFS/HFS+ and
      # NTFS treat `Foo/index.html` and `foo/index.html` as the same file, and
      # APFS additionally folds the NFD and NFC spellings of one accented name
      # together — so two pages whose URLs differ only that way overwrite each
      # other there while both publish fine on a case-sensitive host.
      def output_fold_key(key : String) : String
        # NFC is the identity for ASCII, which is nearly every URL, and this
        # runs once per page per build.
        return key.downcase if key.ascii_only?
        key.unicode_normalize(:nfc).downcase
      end

      # Does the filesystem that `reference` lives on fold letter case in file
      # names? Probed rather than inferred from the platform: a macOS
      # developer can format a case-SENSITIVE APFS volume and a Linux box can
      # mount a case-insensitive one, so `flag?(:darwin)` would both suppress
      # pages that would have published and miss pages that won't.
      #
      # The probe writes nothing into the user's tree: it flips the case of
      # the ASCII letters of an existing path and asks whether the result
      # names the SAME file. Inode identity, not mere existence — a directory
      # that genuinely holds both spellings must not read as case-folding.
      # Anything inconclusive (no ASCII letters to flip, an unreadable path)
      # answers "case sensitive", which is the behavior that predates this
      # check.
      def case_folding_fs?(reference : String) : Bool
        original = File.expand_path(reference)
        flipped = original.gsub do |char|
          if char.ascii_lowercase?
            char.upcase
          elsif char.ascii_uppercase?
            char.downcase
          else
            char
          end
        end
        return false if flipped == original

        info = File.info?(original)
        return false unless info
        other = File.info?(flipped)
        return false unless other
        info.same_file?(other)
      rescue File::Error
        false
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

      # `path` with every symlink resolved, including when it does not exist
      # yet: resolve the deepest existing ancestor and re-append the missing
      # tail. A not-yet-created destination is the normal case (`-o export` on
      # a fresh checkout), so bailing out on a missing leaf would leave exactly
      # the paths a destination guard exists for unresolved.
      #
      # Guards that compare a requested destination against project
      # directories MUST resolve both sides through here: `File.expand_path`
      # is purely lexical, so `ln -s . selfdir` made `-o selfdir` look like a
      # dedicated sibling directory while it named the project root.
      #
      # Falls back to the given path when resolution fails (broken link,
      # symlink loop, unreadable ancestor) — lexical matching is what the
      # callers had before, so a failure never loosens a guard below its old
      # behavior.
      def resolved_real_path(path : String) : String
        suffix = [] of String
        current = path
        until File.exists?(current)
          parent = File.dirname(current)
          return path if parent == current
          suffix << File.basename(current)
          current = parent
        end
        real = File.realpath(current)
        suffix.reverse_each { |part| real = File.join(real, part) }
        real
      rescue File::Error | IO::Error
        path
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
