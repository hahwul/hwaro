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
      DANGEROUS_SHELL_PATTERNS = /[|;&`$]|\bsudo\b|\brm\s+-rf\b/

      private def deploy_via_command(
        target : Models::DeploymentTarget,
        source_dir : String,
        command : String,
        effective : EffectiveOptions,
      ) : Bool
        Logger.heading("deploy", target.name)
        warn_unapplied_target_options(target)
        require_non_empty_source!(source_dir, effective) if command_reads_source?(command)
        expanded = expand_placeholders(command, source_dir, target)
        env = {
          "HWARO_DEPLOY_TARGET" => target.name,
          "HWARO_DEPLOY_URL"    => target.url,
          "HWARO_DEPLOY_SOURCE" => source_dir,
        }

        if effective.dry_run
          Logger.info "Dry run: would run command:"
          Logger.info "  #{expanded}"
          return true
        end

        # Always show the command that will be executed
        Logger.info "  Command: #{expanded}"

        # Warn and require confirmation for commands with shell
        # metacharacters. The *template* is what the author wrote; the
        # placeholder values are single-quoted, so judging the expansion
        # flagged a project living under `r&d/` or `$work/` and blocked every
        # non-interactive s3/gs/az deploy from it.
        needs_confirm = effective.confirm
        if !effective.force && DANGEROUS_SHELL_PATTERNS.matches?(command)
          Logger.warn "Deploy command contains shell metacharacters (pipes, redirects, subshells, etc.)."
          needs_confirm = true
        end

        if needs_confirm && !confirm?("Run deploy command for '#{target.name}'?")
          Logger.warn "Cancelled."
          return true
        end

        status, stderr = run_deploy_command(expanded, env)
        unless status.success?
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
            message: "Deploy command failed (#{how}): #{expanded}",
            hint: "Inspect the stderr above for details from the deploy tool.",
          )
        end

        Logger.info "" if Logger.color_enabled?
        Logger.outcome("deployed", target.name)
        true
      end

      # Run a deploy command, streaming its output as it arrives. Deploy tools
      # run for minutes (`aws s3 sync`, `rsync` over a slow link); buffering
      # until exit left the terminal silent the whole time, and stderr — where
      # those tools print warnings and progress — was dropped entirely unless
      # the command failed. stdout goes through `Logger.info` (so `--quiet`
      # and `--json` keep it off stdout), stderr to `Logger.err_io`.
      #
      # stdin is handed to the child only on an interactive run, so a tool
      # that asks to confirm or log in can be answered; pipes, CI and `--json`
      # keep it closed so nothing blocks on input that will never come.
      #
      # Returns the exit status and the captured stderr.
      private def run_deploy_command(command : String, env : Hash(String, String)) : {Process::Status, String}
        input = CLI::Prompt.interactive? && !CLI::Runner.json_mode? ? Process::Redirect::Inherit : Process::Redirect::Close
        process = Process.new(command, shell: true, env: env, input: input,
          output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)

        stderr = IO::Memory.new
        # Both pipes are drained concurrently (one fills and blocks the
        # child otherwise); the lock keeps their lines whole when the logger
        # writes both streams to one IO.
        lock = Mutex.new
        drained = Channel(Nil).new
        spawn do
          process.error.each_line do |line|
            lock.synchronize do
              stderr.puts line
              Logger.err_io.puts "  #{line}" unless Logger.quiet?
            end
          end
        ensure
          drained.send(nil)
        end
        process.output.each_line do |line|
          lock.synchronize { Logger.info "  #{line}" }
        end
        drained.receive

        {process.wait, stderr.to_s}
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

      # Pattern for `{name}` placeholder tokens in command templates. A `$`
      # in front makes it shell parameter expansion (`${HWARO_DEPLOY_TARGET}`),
      # which is passed through untouched instead of rejected as unknown.
      private COMMAND_PLACEHOLDER_RE = /(?<!\$)\{([a-zA-Z_][\w-]*)\}/

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
          when "source" then shell_escape(source_dir)
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
        unresolved = command.scan(COMMAND_PLACEHOLDER_RE)
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

      # Escape a string for safe interpolation into a shell command.
      # Wraps the value in single quotes and escapes any embedded single quotes.
      # Strips null bytes which can bypass shell escaping.
      private def shell_escape(value : String) : String
        sanitized = value.gsub("\0", "")
        "'" + sanitized.gsub("'", "'\\''") + "'"
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
