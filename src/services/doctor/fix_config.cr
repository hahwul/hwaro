# Doctor — `doctor --fix` / `--approve` config rewriting.
#
# Split out of doctor.cr, which keeps the require order, the Doctor ivars
# and `run`. Parts only define or reopen types: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Doctor
      # A surgical edit `--fix` applied to an existing config value.
      # Distinct from "section appends" because it modifies the user's
      # real configuration rather than adding commented documentation.
      record ValueFix, field : String, before : String, after : String do
        include JSON::Serializable
      end

      # Outcome of `fix_config`. `dry_run = true` populates the same
      # fields without writing, so the CLI can show a preview.
      record FixSummary,
        sections_added : Array(String) = [] of String,
        value_fixes : Array(ValueFix) = [] of ValueFix,
        dry_run : Bool = false do
        include JSON::Serializable

        def empty? : Bool
          sections_added.empty? && value_fixes.empty?
        end
      end

      # Apply real fixes (Phase 1: value corrections like base_url trailing slash)
      # and optionally approve/add recommended config sections (Phase 2).
      #
      # - apply_value_fixes: Phase 1 value corrections. `--fix` and `--full`
      #   enable this; a bare `--approve` must NOT edit real values — the
      #   documented model is "--fix normalizes, --approve adds sections".
      # - approve_sections: When true, doctor will add the recommended/optional
      #   config sections as commented documentation (`--approve` / `--full`).
      #
      # This separation makes --fix focused on corrections, while --approve / --full
      # controls bringing in the larger set of recommendations.
      def fix_config(approve_sections : Bool = false, dry_run : Bool = false, apply_value_fixes : Bool = true) : FixSummary
        unless File.exists?(@config_path)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Config file not found: #{@config_path}",
            hint: "Run 'hwaro init' to scaffold a project, or cd into a directory containing config.toml.",
          )
        end

        raw_text = readable_config_toml
        unless raw_text
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Cannot read #{@config_path}",
            hint: "Check file permissions and retry.",
          )
        end

        raw = parse_config_toml(raw_text)
        unless raw
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "#{@config_path} has TOML parse errors; refusing to --fix.",
            hint: "Fix the TOML syntax first (run 'hwaro doctor' to see the parse error), then re-run 'hwaro doctor --fix'.",
          )
        end

        # Phase 1: surgical value edits. Operate on the raw text so we
        # preserve formatting, comments, and ordering — the parsed TOML
        # tree has no high-fidelity round-trip writer in stdlib.
        current_text = raw_text
        value_fixes = [] of ValueFix

        if apply_value_fixes
          if applied = trim_base_url_trailing_slash(current_text)
            current_text = applied[:text]
            value_fixes << applied[:fix]
          end

          if applied = clamp_sitemap_priority(current_text)
            current_text = applied[:text]
            value_fixes << applied[:fix]
          end
        end

        # Phase 2: section appends — only when the user opted in via
        # --approve / --full; plain --fix stays focused on value
        # corrections and never injects dozens of commented sections.
        snippets = [] of String
        added = [] of String

        if approve_sections
          # Safety net against re-appending: even though the missing list
          # was just computed from the same snapshot, re-scan the (value-
          # fixed) text we are actually about to write.
          mentioned = mentioned_sections(current_text)
          missing_config_sections(raw_text, raw).each do |key|
            next if mentioned.includes?(key)
            if snippet = config_snippet_for(key)
              snippets << snippet
              added << key
            end
          end
        end

        summary = FixSummary.new(sections_added: added, value_fixes: value_fixes, dry_run: dry_run)
        return summary if summary.empty?
        return summary if dry_run

        # Write atomically: compose the final file contents in a temp
        # file beside `config.toml`, then `File.rename` into place so a
        # mid-write interruption (SIGINT, disk full) can't leave a
        # partially-appended config behind. The original file's
        # permissions carry over to the temp file — without that, the
        # rename would silently reset e.g. a 0600 config to the default
        # umask.
        #
        # `rename` REPLACES the path it targets, so it must target the
        # file the config actually lives in: aimed at a symlink
        # (`config.toml -> shared/config.toml`, a common monorepo/theme
        # layout) it dropped a regular file on top of the link and left
        # the real config untouched — doctor reported the fix as applied
        # while the site kept building from the unfixed file.
        target_path = resolved_config_path
        sweep_abandoned_temp_files(target_path)
        tmp_path = "#{target_path}.#{Process.pid}.hwaro-tmp"
        begin
          original_permissions = File.info(target_path).permissions
          File.open(tmp_path, "w") do |f|
            f.print(current_text)
            f.print("\n") unless current_text.ends_with?("\n")
            snippets.each { |s| f.print(s) }
          end
          File.chmod(tmp_path, original_permissions)
          File.rename(tmp_path, target_path)
        rescue ex : IO::Error | File::Error
          # Clean the half-written temp file so re-running isn't blocked.
          # Cleanup is best-effort: it must never replace the classified
          # I/O error below with a raw one (a directory sitting on the temp
          # path made `File.delete` raise straight out of this handler).
          begin
            File.delete(tmp_path) if File.file?(tmp_path)
          rescue err : IO::Error | File::Error
            Logger.debug "Doctor: could not remove temp file #{tmp_path}: #{err.message}"
          end
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "Failed to update #{@config_path}: #{ex.message}",
            hint: "Check file permissions and available disk space, then retry.",
          )
        end

        summary
      end

      # Remove temp files left behind by runs that are no longer alive.
      #
      # The pid in the temp name is what keeps two concurrent `--fix` runs
      # from renaming each other's half-written file into place. But a run
      # killed outside our control (SIGKILL, power loss) never reaches the
      # rescue that cleans up, and with a unique name per run nothing else
      # ever would either — each crash would leave one more file in the
      # project directory. Only files whose owning process is gone are
      # swept, so a concurrent run's file is left alone.
      private def sweep_abandoned_temp_files(target_path : String)
        dir = File.dirname(target_path)
        prefix = "#{File.basename(target_path)}."
        suffix = ".hwaro-tmp"
        Dir.each_child(dir) do |entry|
          next unless entry.starts_with?(prefix) && entry.ends_with?(suffix)
          pid = entry[prefix.size...(entry.size - suffix.size)].to_i?
          next unless pid && pid > 0
          next if pid == Process.pid || Process.exists?(pid)
          path = File.join(dir, entry)
          File.delete(path) if File.file?(path)
        end
      rescue ex : IO::Error | File::Error
        Logger.debug "Doctor: could not sweep temp files beside #{target_path}: #{ex.message}"
      end

      # `@config_path` with symlinks resolved, so a rewrite lands on the
      # real file. Falls back to the literal path when the link can't be
      # resolved — the write then fails with the classified error above
      # rather than here.
      private def resolved_config_path : String
        return @config_path unless File.symlink?(@config_path)
        File.realpath(@config_path)
      rescue ex : File::Error
        Logger.debug "Doctor: cannot resolve #{@config_path}: #{ex.message}"
        @config_path
      end

      # Strip trailing slashes from a top-level `base_url = "..."` line.
      # Top-level only — anything past the first `[section]` header is
      # left alone. Handles both TOML basic (`"..."`) and literal
      # (`'...'`) strings; doctor's advisory fires on either form, so
      # `--fix` must be able to repair either form too. Returns nil when
      # no edit is needed (no match, empty value, or already slash-free)
      # so the caller can skip emitting a spurious ValueFix.
      private def trim_base_url_trailing_slash(text : String) : NamedTuple(text: String, fix: ValueFix)?
        lines = text.split('\n', remove_empty: false)
        in_string = multiline_string_line_states(lines)
        lines.each_with_index do |line, idx|
          # A base_url-looking line inside a TOML multi-line string is
          # string CONTENT — editing it corrupts user data, and a
          # `[section]`-looking line in one must not end the top-level
          # scan early either.
          next if in_string[idx]
          break if line =~ /^\s*\[/ # entered a section table; base_url is top-level only
          # `[^"']*` refuses values containing either quote char, so a
          # string this regex can't round-trip safely is skipped rather
          # than mangled.
          next unless m = line.match(/^([ \t]*)base_url([ \t]*=[ \t]*)(["'])([^"']*)\3(.*)$/)
          quote = m[3]
          url = m[4]
          next if url.empty?
          next unless url.ends_with?("/")
          trimmed = url.rstrip('/')
          next if trimmed.empty? # avoid mangling oddities like base_url = "/"
          lines[idx] = "#{m[1]}base_url#{m[2]}#{quote}#{trimmed}#{quote}#{m[5]}"
          return {text: lines.join('\n'), fix: ValueFix.new("base_url", url, trimmed)}
        end
        nil
      end

      # Clamp the sitemap priority to [0.0, 1.0]. Walks the file
      # line-by-line so we only ever rewrite a priority that actually
      # belongs to the sitemap config: `priority = …` inside the
      # `[sitemap]` table, or a top-level dotted `sitemap.priority = …`
      # key. Any other `priority` key is left intact.
      #
      # Header tracking must recognize EVERY table header form —
      # `[name]`, `[[array.of.tables]]`, optional trailing comment —
      # because a header that fails to match leaves the previous state
      # in place. The old `[name]`-only regex skipped `[[taxonomies]]`
      # style headers entirely, so `in_sitemap` stayed true across them
      # and `--fix` clamped priority keys in unrelated tables further
      # down the file — silent corruption of user data.
      private def clamp_sitemap_priority(text : String) : NamedTuple(text: String, fix: ValueFix)?
        lines = text.split('\n', remove_empty: false)
        in_string = multiline_string_line_states(lines)
        in_sitemap = false
        top_level = true
        number = /[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/
        lines.each_with_index do |line, idx|
          # Lines inside a TOML multi-line string are string CONTENT: a
          # priority-looking line there must never be clamped, and a
          # header-looking line there must not flip in_sitemap/top_level.
          next if in_string[idx]
          if header = line.match(/^\s*\[\[?\s*([^\[\]]+?)\s*\]\]?\s*(?:#.*)?$/)
            in_sitemap = (header[1] == "sitemap")
            top_level = false
            next
          end

          # The dotted spelling is only the sitemap's priority while we
          # are still above the first table header; after that it would
          # name `<current_table>.sitemap.priority` instead.
          key = if in_sitemap
                  /priority/
                elsif top_level
                  /sitemap[ \t]*\.[ \t]*priority/
                else
                  next
                end

          next unless m = line.match(/^([ \t]*)(#{key})([ \t]*=[ \t]*)(#{number})(.*)$/)
          val = m[4].to_f?
          next unless val
          next if 0.0 <= val <= 1.0
          clamped = val.clamp(0.0, 1.0)
          # Render the clamped value with at least one fractional digit
          # so it stays a TOML float (mirrors how the scaffolded snippet
          # writes it: `priority = 0.5`).
          after = clamped == clamped.to_i ? "#{clamped.to_i}.0" : clamped.to_s
          lines[idx] = "#{m[1]}#{m[2]}#{m[3]}#{after}#{m[5]}"
          return {text: lines.join('\n'), fix: ValueFix.new("sitemap.priority", m[4], after)}
        end
        nil
      end
    end
  end
end
