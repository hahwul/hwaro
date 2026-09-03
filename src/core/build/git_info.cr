# Git metadata for content pages (`[git]` in config.toml).
#
# ONE `git log` invocation per build walks the whole `content/` history and
# is parsed into a `path => Models::GitInfo` map keyed by content-relative
# path — never one process per page, which is what makes the feature usable
# on sites with thousands of pages. Collection runs in the Initialize phase
# (alongside data files) so the parse phase can fill `page.git` and the
# `updated`/`date` fallbacks before URLs, sorting or SEO surfaces read them.
#
# Every failure mode degrades to "no git info" with a single warning and
# never aborts the build: no `git` binary, a site outside any repository, a
# shallow clone (history truncated, so `lastmod` may be wrong), or a file
# that is simply not committed yet (no entry → `page.git` is nil and no
# fallback applies).

require "../../models/git_info"
require "../../utils/logger"

module Hwaro
  module Core
    module Build
      module GitInfo
        extend self

        # Each commit header is a NUL-led record so it can never be confused
        # with a pathname line: `\0<hash>\0<author date, RFC 3339>\0<name>\0<email>`.
        # `--name-only` then lists the touched paths one per line.
        LOG_FORMAT = "%x00%H%x00%aI%x00%an%x00%ae"

        # Collect commit metadata for every file under `content_dir`, keyed
        # by path relative to it. Returns nil (after warning) when git
        # history is unavailable for any reason.
        def collect(content_dir : String = "content") : Hash(String, Models::GitInfo)?
          return unless Dir.exists?(content_dir)

          output = run_git(content_dir, ["-c", "core.quotePath=false", "log", "--no-merges", "--relative",
                                         "--format=#{LOG_FORMAT}", "--name-only", "--", "."])
          return unless output

          warn_if_shallow(content_dir)
          parse_log(output)
        end

        # Parse `git log` output produced with LOG_FORMAT + `--name-only`.
        # The log is newest-first, so the first header a path appears under
        # is its latest commit (hash, author, lastmod); `first_commit` is the
        # minimum author date over every commit listing the path (rebased or
        # cherry-picked history can leave author dates out of walk order).
        def parse_log(output : String) : Hash(String, Models::GitInfo)
          result = {} of String => Models::GitInfo
          current : Models::GitInfo? = nil

          output.each_line do |line|
            next if line.empty?
            if line.starts_with?('\0')
              current = parse_header(line)
              next
            end
            next unless header = current
            path = unquote_path(line)
            next if path.empty?
            if existing = result[path]?
              if header.lastmod < existing.first_commit
                result[path] = existing.copy_with(first_commit: header.lastmod)
              end
            else
              result[path] = header
            end
          end

          result
        end

        # `\0<hash>\0<date>\0<name>\0<email>` → a GitInfo whose lastmod and
        # first_commit both hold this commit's author date. Nil for a header
        # that does not fit (a malformed date), which also drops the file
        # lines that follow it — better than attributing them to the
        # previous commit.
        private def parse_header(line : String) : Models::GitInfo?
          fields = line.split('\0')
          return unless fields.size >= 5
          hash = fields[1]
          time = Time.parse_rfc3339(fields[2]) rescue nil
          return unless time
          return if hash.empty?
          Models::GitInfo.new(
            hash: hash,
            lastmod: time,
            first_commit: time,
            author_name: fields[3],
            author_email: fields[4],
          )
        end

        # With `core.quotePath=false` git still C-quotes a path that holds a
        # control character, a double quote or a backslash. Undo that so the
        # key matches the page path the ReadContent phase derived from disk.
        def unquote_path(raw : String) : String
          return raw unless raw.size >= 2 && raw.starts_with?('"') && raw.ends_with?('"')
          inner = raw[1, raw.size - 2]
          return inner unless inner.includes?('\\')

          bytes = IO::Memory.new
          i = 0
          while i < inner.bytesize
            byte = inner.byte_at(i)
            if byte == '\\'.ord && i + 1 < inner.bytesize
              nxt = inner.byte_at(i + 1)
              case nxt
              when 'n'.ord  then bytes.write_byte('\n'.ord.to_u8); i += 2
              when 't'.ord  then bytes.write_byte('\t'.ord.to_u8); i += 2
              when 'r'.ord  then bytes.write_byte('\r'.ord.to_u8); i += 2
              when '\\'.ord then bytes.write_byte('\\'.ord.to_u8); i += 2
              when '"'.ord  then bytes.write_byte('"'.ord.to_u8); i += 2
              when '0'.ord..'7'.ord
                # Up to three octal digits encode one raw byte (UTF-8 paths
                # arrive as a run of these when quoting is forced).
                value = 0
                digits = 0
                while digits < 3 && i + 1 + digits < inner.bytesize
                  d = inner.byte_at(i + 1 + digits)
                  break unless d >= '0'.ord && d <= '7'.ord
                  value = value * 8 + (d - '0'.ord)
                  digits += 1
                end
                bytes.write_byte(value.to_u8!)
                i += 1 + digits
              else
                bytes.write_byte(byte)
                i += 1
              end
            else
              bytes.write_byte(byte)
              i += 1
            end
          end
          String.new(bytes.to_slice)
        end

        # Run `git` inside `content_dir`, returning stdout or nil after a
        # single warning that names the reason.
        private def run_git(content_dir : String, args : Array(String)) : String?
          stdout = IO::Memory.new
          stderr = IO::Memory.new
          status = Process.run("git", args, chdir: content_dir, output: stdout, error: stderr)
          if status.success?
            return stdout.to_s
          end

          reason = stderr.to_s.lines.first?.try(&.strip) || "exit #{status.exit_code}"
          if reason.includes?("not a git repository")
            Logger.warn "[git] enabled, but #{content_dir}/ is not inside a git repository — page.git is unavailable and no lastmod fallback applies."
          else
            Logger.warn "[git] enabled, but `git log` failed (#{reason}) — page.git is unavailable and no lastmod fallback applies."
          end
          nil
        rescue ex : IO::Error | RuntimeError
          # `Process.run` raises when the executable cannot be spawned at all
          # (no `git` on PATH).
          Logger.warn "[git] enabled, but the git binary could not be run (#{ex.message}) — page.git is unavailable and no lastmod fallback applies."
          nil
        end

        # A shallow clone (`--depth N`, the GitHub Actions checkout default)
        # holds only the newest commits, so every older file appears to have
        # been created — and last modified — at the truncation boundary.
        private def warn_if_shallow(content_dir : String)
          stdout = IO::Memory.new
          status = Process.run("git", ["rev-parse", "--is-shallow-repository"], chdir: content_dir, output: stdout, error: Process::Redirect::Close)
          return unless status.success? && stdout.to_s.strip == "true"
          Logger.warn "[git] the repository is a shallow clone — page.git.lastmod/first_commit may be wrong for files older than the clone depth. Fetch full history (e.g. actions/checkout with `fetch-depth: 0`)."
        rescue IO::Error | RuntimeError
          # The log call above already ran git successfully; a failure here is
          # not worth a second warning.
        end
      end
    end
  end
end
