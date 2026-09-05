# Doctor — raw config.toml scanning (section mentions, multiline-string state, parsing).
#
# Split out of doctor.cr, which keeps the require order, the Doctor ivars
# and `run`. Parts only define or reopen types: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Doctor
      # Returns the list of config section keys missing from the user's config.toml.
      # On I/O or TOML parse failure, returns an empty array — those paths are
      # already reported by `check_config` as classified issues, so silent-empty
      # here lets the main run loop carry on without double-reporting. Callers
      # that need a clearer signal (e.g. `fix_config`) should probe the file
      # directly via `readable_config_toml` / `parse_config_toml`.
      def missing_config_sections : Array(String)
        raw_text = readable_config_toml
        return [] of String unless raw_text

        raw = parse_config_toml(raw_text)
        return [] of String unless raw

        missing_config_sections(raw_text, raw)
      end

      # Snapshot variant: computes against an already-read text + parsed
      # table so `fix_config` decides everything from the single read it
      # performed up front — no second `File.read` that could observe a
      # different file than the one it's about to rewrite.
      private def missing_config_sections(raw_text : String, raw : TOML::Table) : Array(String)
        mentioned = mentioned_sections(raw_text)
        missing = [] of String

        KNOWN_CONFIG_SECTIONS.each_key do |key|
          unless raw.has_key?(key) || mentioned.includes?(key)
            missing << key
          end
        end

        # Check sub-sections (only when parent section exists)
        KNOWN_SUB_SECTIONS.each_key do |parent, child|
          sub_key = "#{parent}.#{child}"
          if parent_hash = raw[parent]?.try(&.as_h?)
            unless parent_hash.has_key?(child) || mentioned.includes?(sub_key)
              missing << sub_key
            end
          end
          # If parent doesn't exist at all, don't report sub-section
        end

        missing
      end

      # Every section path mentioned by a table header in the config
      # text — active (`[pwa]`, `[[menus.main]]`) or commented out
      # (`# [pwa]`, `# [[menus.main]]`) — plus each dotted ancestor, so
      # `[[menus.main]]` also covers "menus". Lowercased for lookups.
      #
      # This single scan backs both the missing-section report and the
      # `--fix` duplicate guard so the two can't drift apart. They used
      # to be separate scans, and neither recognized `[[array.tables]]`
      # headers: the commented [menus] snippet only contains
      # `# [[menus.main]]` lines, so every `--approve` run re-reported
      # "menus" as missing and appended the snippet again, growing the
      # config forever.
      private def mentioned_sections(text : String) : Set(String)
        found = Set(String).new
        lines = text.split('\n')
        in_string = multiline_string_line_states(lines)
        lines.each_with_index do |line, idx|
          # A `[menus]`-looking line inside a TOML multi-line string is
          # string CONTENT, not a header; counting it suppressed the real
          # missing-section detection.
          next if in_string[idx]
          next unless m = line.match(/^\s*(?:#\s*)?\[\[?\s*([^\[\]]+?)\s*\]\]?/)
          parts = m[1].downcase.split('.').map(&.strip)
          parts.each_index { |i| found << parts[0..i].join('.') }
        end
        found
      end

      # TOML multi-line strings (`"""…"""` / `'''…'''`) can span lines
      # whose text looks exactly like a key assignment or a table header.
      # Every line-oriented scanner in this service must skip those lines:
      # matching them edits user DATA (violating the "--fix preserves
      # content byte-exactly outside the fixed region" invariant), flips
      # the header-tracking state, and fools `mentioned_sections`. Returns,
      # for each line of `lines`, whether that line STARTS inside a
      # multi-line string.
      private def multiline_string_line_states(lines : Array(String)) : Array(Bool)
        states = Array(Bool).new(lines.size)
        delim = nil.as(Char?)
        lines.each do |line|
          states << !delim.nil?
          delim = advance_multiline_string_state(line, delim)
        end
        states
      end

      # Advance the multi-line-string tracker across one line. `delim` is
      # the quote character of the currently open multi-line string (nil
      # when outside one). Handles delimiters that open and close on the
      # same line, backslash escapes in basic strings, and single-line
      # strings/comments whose quote characters could otherwise fake an
      # opener.
      private def advance_multiline_string_state(line : String, delim : Char?) : Char?
        chars = line.chars
        i = 0
        while i < chars.size
          c = chars[i]

          if d = delim
            if c == '\\' && d == '"'
              i += 2 # escaped char in a basic multi-line string
            elsif c == d && chars[i + 1]? == d && chars[i + 2]? == d
              # Consume the whole quote run: TOML allows one or two extra
              # quote chars of CONTENT adjacent to the delimiter (`""""`
              # is `"` + close), and the closing delimiter is the last
              # three of the run.
              i += 3
              while chars[i]? == d
                i += 1
              end
              delim = nil
            else
              i += 1
            end
            next
          end

          case c
          when '#'
            break # comment — nothing after it can open a string
          when '"', '\''
            if chars[i + 1]? == c && chars[i + 2]? == c
              delim = c
              i += 3
            else
              # Single-line string: skip to its closing quote so a quote
              # char inside it can't fake a multi-line opener.
              i += 1
              while i < chars.size
                ch = chars[i]
                if ch == '\\' && c == '"'
                  i += 2
                elsif ch == c
                  i += 1
                  break
                else
                  i += 1
                end
              end
            end
          else
            i += 1
          end
        end
        delim
      end

      # Sections that are advanced/niche or low-value for most users.
      # These are now treated as opt-in by default (not auto-suggested in normal doctor,
      # and not added by plain --fix unless the user explicitly wants them).
      #
      # Goal: Reduce config bloat and the "you should add all these things" pressure.
      OPTIONAL_SECTIONS = Set{
        # Very specialized / rarely needed for most sites
        "pwa", "amp",
        # Advanced/optional image features
        "image_processing", "image_processing.lqip", "og.auto_image",
        # Power-user / deployment related
        "build", "deployment", "permalinks", "auto_includes", "links",
        # Asset pipeline (many prefer manual or external bundlers)
        "assets",
        # Built-in Sass compilation (opt-in)
        "sass",
        # Useful but not essential to nag about
        "related", "series", "pagination",
        # Git metadata — only meaningful inside a repository with full history
        "git",
        # Navigation menus — many sites hardcode nav in the theme instead
        "menus",
        # Content authoring niceties
        "content.new",
        # Nice-to-have SEO / crawler files (most people can add manually if needed)
        "robots", "llms",
        # Dev server customization (only needed when reproducing specific headers)
        "serve",
      }

      # Read `config.toml` as text. Returns nil on I/O failure
      # (permission denied, missing file, etc.) so callers can branch
      # without nesting another begin/rescue.
      private def readable_config_toml : String?
        return unless File.exists?(@config_path)
        File.read(@config_path)
      rescue ex : IO::Error | File::Error
        Logger.debug "Doctor: cannot read #{@config_path}: #{ex.message}"
        nil
      end

      # Parse the raw `config.toml` text. Returns nil on TOML parse
      # failure; callers already downstream of `check_config` have seen
      # the classified error so silent-nil here avoids double-reporting.
      # The rescue is narrowed to `TOML::ParseException` so any other
      # unexpected error propagates rather than being silently swallowed.
      private def parse_config_toml(raw_text : String) : TOML::Table?
        TOML.parse(raw_text)
      rescue ex : TOML::ParseException
        Logger.debug "Doctor: TOML parse error in #{@config_path}: #{ex.message}"
        nil
      end

      # Get the TOML snippet for a missing config section
      private def config_snippet_for(key : String) : String?
        ConfigSnippets.doctor_snippet_for(key)
      end
    end
  end
end
