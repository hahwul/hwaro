# Deployer — command targets (placeholders, shell escaping, s3/gs/az auto-commands, file:// resolution).
#
# Reopens `Services::Deployer`; deployer.cr keeps the result records, the
# three entry points (plan / run / deploy_structured) and per-target
# dispatch. Parts only reopen the class: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Deployer
      # Shell metacharacters that indicate potentially dangerous commands.
      # These are not inherently bad but warrant user attention when present
      # in deploy commands, especially from remote scaffolds.
      # Windows adds cmd.exe's `%VAR%` expansion and `^` escape.
      DANGEROUS_SHELL_PATTERNS = {% if flag?(:windows) %} /[|;&`$%^]|\bsudo\b|\brm\s+-rf\b/ {% else %} /[|;&`$]|\bsudo\b|\brm\s+-rf\b/ {% end %}

      private def deploy_via_command(
        target : Models::DeploymentTarget,
        source_dir : String,
        command : String,
        effective : EffectiveOptions,
        uploads : Array(MetadataUpload) = [] of MetadataUpload,
      ) : Bool
        Logger.heading("deploy", target.name)
        warn_unapplied_target_options(target)
        if command_reads_source?(command)
          # The one filesystem read a command target does; classified here
          # rather than around the whole run, so a closed stdout later on is
          # not blamed on the source or destination.
          classify_io_errors(target) { require_non_empty_source!(source_dir, effective) }
        end
        expanded = expand_placeholders(command, source_dir, target)
        env = {
          "HWARO_DEPLOY_TARGET" => target.name,
          "HWARO_DEPLOY_URL"    => target.url,
          "HWARO_DEPLOY_SOURCE" => command_source(source_dir),
        }

        if effective.dry_run
          Logger.info "Dry run: would run command:"
          Logger.info "  #{expanded}"
          log_planned_uploads(uploads) unless uploads.empty?
          return true
        end

        # Always show the command that will be executed
        Logger.info "  Command: #{expanded}"

        # Warn and require confirmation for commands with shell
        # metacharacters. Judge the *template* the author wrote: placeholder
        # values are single-quoted, so judging the expansion flagged a project
        # living under `r&d/` or `$work/` and blocked every non-interactive
        # s3/gs/az deploy from it. The quoting only holds where the
        # placeholder stands as a bare word, though — inside `"…"` or `'…'`
        # the template's own quotes undo it — so a quoted placeholder is
        # still judged by its expanded value.
        needs_confirm = effective.confirm
        #
        # cmd.exe (Windows) expands `%NAME%` even inside the double quotes a
        # bare placeholder gets, so a `%` a value brought in is judged too.
        risky = DANGEROUS_SHELL_PATTERNS.matches?(command) ||
                (quoted_placeholder?(command) && DANGEROUS_SHELL_PATTERNS.matches?(expanded)) ||
                ({{ flag?(:windows) }} && expanded.count('%') > command.count('%'))
        if !effective.force && risky
          Logger.warn "Deploy command contains shell metacharacters (pipes, redirects, subshells, etc.)."
          needs_confirm = true
        end
        if !effective.force && {{ flag?(:windows) }} && (percent = metadata_percent_warning(target.url, uploads))
          Logger.warn percent
          needs_confirm = true
        end

        if needs_confirm && !confirm?("Run deploy command for '#{target.name}'?")
          Logger.warn "Cancelled."
          return true
        end

        status, stderr = run_deploy_command(expanded, env)
        raise_command_failed!(status, stderr, expanded) unless status.success?
        run_metadata_uploads(target, uploads, env)

        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", target.name)
        true
      end

      private def raise_command_failed!(status : Process::Status, stderr : String, command : String) : NoReturn
        # A quiet run streamed nothing, so surface the tool's stderr before
        # raising; the classified error itself carries only the summary.
        if Logger.quiet? && !stderr.empty?
          stderr.each_line { |line| Logger.error "  #{line}" }
        end
        # `exit_code` raises for a signal-terminated child (a killed
        # `rsync`, an OOM-killed uploader), which crashed the deploy with
        # an unclassified RuntimeError instead of reporting the failure.
        how = if code = status.exit_code?
                "exit #{code}"
              else
                "terminated by signal #{status.exit_signal?.try(&.to_s) || "?"}"
              end
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_IO,
          message: "Deploy command failed (#{how}): #{command}",
          hint: "Inspect the stderr above for details from the deploy tool.",
        )
      end

      # Run a deploy command, streaming its output as it arrives. Deploy tools
      # run for minutes (`aws s3 sync`, `rsync` over a slow link); buffering
      # until exit left the terminal silent the whole time, and stderr — where
      # those tools print warnings and progress — was dropped entirely unless
      # the command failed. stdout goes through `Logger.info` (so `--quiet`
      # and `--json` keep it off stdout), stderr to `Logger.err_io`.
      #
      # stdin is handed to the child only on a visible interactive run, so a
      # tool that asks to confirm or log in can be answered; pipes, CI,
      # `--json` and `--quiet` (which hides the prompt) keep it closed so
      # nothing blocks on input that will never come.
      #
      # Both pipes are always drained to EOF, even after echoing them fails
      # (`hwaro deploy | head`, a closed stderr): a pipe nobody reads fills
      # up and blocks the deploy tool forever. The output was only ever
      # informational, so the deploy itself runs to completion either way.
      #
      # Returns the exit status and the stderr captured for a quiet run.
      private def run_deploy_command(command : String, env : Hash(String, String)) : {Process::Status, String}
        quiet = Logger.quiet?
        input = CLI::Prompt.interactive? && !quiet ? Process::Redirect::Inherit : Process::Redirect::Close
        process = Process.new(Utils::CommandRunner.shell_command(command), shell: true, env: env, input: input,
          output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)

        begin
          captured = IO::Memory.new
          # The lock keeps lines whole when the logger writes both streams to
          # one IO (as specs do).
          lock = Mutex.new
          drained = Channel(Nil).new(1)
          spawn do
            echo = true
            process.error.each_line do |line|
              lock.synchronize do
                if quiet
                  captured.puts line
                elsif echo
                  begin
                    Logger.err_io.puts "  #{line}"
                  rescue IO::Error
                    echo = false
                  end
                end
              end
            end
          rescue IO::Error
            # The pipe itself failed; the child sees EPIPE and exits.
          ensure
            drained.send(nil)
          end

          echo = true
          process.output.each_line do |line|
            next unless echo
            begin
              lock.synchronize { Logger.info "  #{line}" }
            rescue IO::Error
              echo = false
            end
          end
          drained.receive
        rescue ex
          # Never leave the deploy tool running behind an exception. Only
          # reached before `wait`, so the pid is still ours to signal.
          begin
            process.terminate
            process.wait
          rescue
          end
          raise ex
        end

        {process.wait, captured.to_s}
      end

      # True when a known placeholder sits inside single or double quotes in
      # the template, where its single-quoted expansion is no longer one
      # inert word: `"{source}"` re-opens the value to `$(…)` expansion.
      private def quoted_placeholder?(command : String) : Bool
        quote = nil.as(Char?)
        escaped = false
        command.each_char_with_index do |char, idx|
          if escaped
            escaped = false
            next
          end
          case char
          when '\\'
            escaped = quote != '\''
          when '\'', '"'
            if quote.nil?
              quote = char
            elsif quote == char
              quote = nil
            end
          when '{'
            next if quote.nil?
            return true if COMMAND_PLACEHOLDERS.any? { |name| command[idx + 1, name.size + 1] == "#{name}}" }
          end
        end
        false
      end

      # A command target only reads the deploy source if its template
      # interpolates `{source}` — which every auto-generated command does.
      private def command_reads_source?(command : String) : Bool
        command.includes?("{source}")
      end

      # Supported placeholders in `command = "..."` templates. Listed
      # here so `expand_placeholders` can produce a helpful error message
      # when an unknown `{foo}` slips through (typo, forward-looking
      # name, etc.) instead of sending the literal to the shell.
      COMMAND_PLACEHOLDERS = {"source", "url", "target"}

      # Pattern for `{name}` placeholder tokens in command templates.
      private COMMAND_PLACEHOLDER_RE = /\{([a-zA-Z_][\w-]*)\}/

      private def expand_placeholders(command : String, source_dir : String, target : Models::DeploymentTarget) : String
        # Validate the ORIGINAL template, then substitute in a single pass:
        # expanded values (paths, urls) may legitimately contain `{...}` text
        # and must be neither re-validated nor re-expanded. The previous
        # sequential gsub let a source path containing a literal `{url}` get
        # substituted a second time, corrupting the command and splicing the
        # shell quoting.
        validate_no_unexpanded_placeholders!(command, target)

        command.gsub(COMMAND_PLACEHOLDER_RE) do |token|
          case $~[1]
          when "source" then shell_escape(command_source(source_dir))
          when "url"    then shell_escape(target.url)
          when "target" then shell_escape(target.name)
          else               token
          end
        end
      end

      # Raise HWARO_E_CONFIG if the command template contains any unknown
      # `{name}` tokens — catches typos like `{srouce}` and forward-
      # looking placeholders (`{bucket}`, `{region}`) before the literal
      # reaches the underlying deploy tool and produces a confusing
      # downstream error.
      private def validate_no_unexpanded_placeholders!(
        command : String,
        target : Models::DeploymentTarget,
      ) : Nil
        # `${NAME}` with an unknown NAME is shell parameter expansion
        # (`${HWARO_DEPLOY_TARGET}`), not a misspelt placeholder; it is left
        # to the shell. `${source}` still expands like `{source}`.
        unresolved = command.scan(COMMAND_PLACEHOLDER_RE)
          .reject { |m| m.begin(0) > 0 && command[m.begin(0) - 1] == '$' && !COMMAND_PLACEHOLDERS.includes?(m[1]) }
          .map { |m| m[1] }
          .uniq!
          .reject { |name| COMMAND_PLACEHOLDERS.includes?(name) }

        return if unresolved.empty?

        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Unknown placeholder(s) in 'command' for target '#{target.name}': " \
                   "#{unresolved.map { |n| "{#{n}}" }.join(", ")}",
          hint: "Supported placeholders: #{COMMAND_PLACEHOLDERS.to_a.sort.map { |n| "{#{n}}" }.join(", ")}.",
        )
      end

      # The source dir as a deploy command sees it. Native Windows tools
      # (xcopy, robocopy, cmd built-ins) read the `/` in `C:/site/public` as
      # a switch. Shared by the real run and `--dry-run`/plan.
      private def command_source(source_dir : String) : String
        {% if flag?(:windows) %}
          source_dir.gsub('/', '\\')
        {% else %}
          source_dir
        {% end %}
      end

      # Escape a string for safe interpolation into a shell command.
      # Wraps the value in single quotes and escapes any embedded single quotes.
      # Strips null bytes which can bypass shell escaping.
      #
      # cmd.exe (Windows) has no single quotes: the value is double-quoted
      # instead. `"` can't appear in a Windows path and the values come from
      # config.toml, a trusted boundary, so an embedded `"` is dropped. A
      # trailing `\` is doubled, or the child's argv parser would read `\"`
      # as a literal quote and run the value into the next argument.
      private def shell_escape(value : String) : String
        sanitized = value.gsub("\0", "")
        {% if flag?(:windows) %}
          %("#{sanitized.delete('"').sub(/(\\+)\z/, "\\1\\1")}")
        {% else %}
          "'" + sanitized.gsub("'", "'\\''") + "'"
        {% end %}
      end

      # Auto-generate a deploy command for known cloud URL schemes.
      # Returns nil if the scheme is not recognized.
      private def auto_command_for_url(url : String, source_dir : String) : String?
        uri = begin
          URI.parse(url)
        rescue URI::Error
          return
        end
        # A missing authority means the URL has no bucket — `s3:/bucket`
        # (one slash) parses as scheme `s3` with path `/bucket`. Handing that
        # to `aws s3 sync` produces an opaque CLI error; returning nil routes
        # it to the unsupported-scheme message that names the target.
        case uri.scheme
        when "s3"
          return if uri.host.nil? || uri.host.try(&.empty?)
          "aws s3 sync {source}/ {url} --delete"
        when "gs"
          return if uri.host.nil? || uri.host.try(&.empty?)
          "gsutil -m rsync -r -d {source}/ {url}"
        when "az"
          # az://container → Azure Blob Storage. Inline the container name
          # (uri.host), shell-escaped — `{url}` would expand to the full
          # `az://container` URL, which the az CLI rejects as a container name.
          container = uri.host
          return if container.nil? || container.empty?
          command = "az storage blob sync --source {source} --container #{shell_escape(container)}"
          # az://container/sub/dir → sync under the sub/dir prefix; dropping
          # the path silently deployed to the container root.
          prefix = uri.path.lchop('/')
          command += " --destination #{shell_escape(URI.decode(prefix))}" unless prefix.empty?
          command
        end
      end

      # Any `scheme:` prefix marks the value as a URL rather than a path. The
      # second character class requires at least two scheme characters so a
      # Windows drive letter (`C:\\out`) stays a local path. Matching on
      # `://` alone let a single-slash typo like `s3:/bucket` fall through to
      # the local-copy branch and create a directory literally named `s3:`.
      private URL_SCHEME_RE = /\A[A-Za-z][A-Za-z0-9+.\-]+:/

      private def local_directory_destination(url : String) : String?
        {% if flag?(:windows) %}
          # `file://C:/out`, `file:///C:/out` (and `file://localhost/C:/out`):
          # URI turns the drive letter into
          # a host (dropping its colon) or keeps a `/` in front of it, and
          # neither is the drive path.
          if drive = url.match(/\Afile:\/\/(?:localhost)?\/?([A-Za-z]:[\/\\][^?#]*)(?:[?#].*)?\z/i)
            return URI.decode(drive[1])
          end
        {% end %}
        if url.matches?(URL_SCHEME_RE)
          uri = URI.parse(url)
          return unless uri.scheme.try(&.downcase) == "file"
          # Allow both file:///abs/path and file://relative/path forms.
          # For a relative form (file://./out, file://relative/path) URI puts the
          # first segment in `host`; prepend it so the path isn't silently
          # rooted at the filesystem root (file://./out must be ./out, not /out).
          # `localhost` is the one host RFC 8089 defines: file://localhost/x
          # is the absolute /x, not a directory named `localhost` under the
          # project.
          path = uri.path
          if (host = uri.host) && !host.empty? && host.downcase != "localhost"
            path = host + path
          end
          return if path.empty?
          # URI components stay percent-encoded (a space is `%20`); decode so
          # `file:///var/www/my%20site` deploys to the real directory instead
          # of creating a literal `my%20site` one.
          return URI.decode(path)
        end

        # No scheme: treat as local path
        url
      rescue ex
        Logger.debug "Failed to parse deploy URL '#{url}': #{ex.message}"
        nil
      end
    end
  end
end
