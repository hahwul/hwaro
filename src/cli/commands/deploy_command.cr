require "option_parser"
require "json"
require "../metadata"
require "../../config/options/deploy_options"
require "../../models/config"
require "../../services/deployer"
require "../../utils/errors"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class DeployCommand
        # Single source of truth for command metadata
        NAME               = "deploy"
        DESCRIPTION        = "Deploy the built site using config.toml"
        POSITIONAL_ARGS    = ["target ..."]
        POSITIONAL_CHOICES = [] of String

        # Flags defined here are used both for OptionParser and completion generation
        FLAGS = [
          FlagInfo.new(short: "-s", long: "--source", description: "Source directory to deploy (default: deployment.source_dir or public)", takes_value: true, value_hint: "DIR"),
          FlagInfo.new(short: nil, long: "--dry-run", description: "Show planned changes without writing"),
          FlagInfo.new(short: nil, long: "--confirm", description: "Ask for confirmation before deploying"),
          FlagInfo.new(short: nil, long: "--force", description: "Force upload/copy (ignore file comparisons)"),
          FlagInfo.new(short: nil, long: "--max-deletes", description: "Maximum number of deletes (default: deployment.maxDeletes or 256, -1 disables)", takes_value: true, value_hint: "N"),
          FlagInfo.new(short: nil, long: "--list-targets", description: "List configured deployment targets and exit"),
          JSON_FLAG,
          ENV_FLAG,
          QUIET_FLAG,
          HELP_FLAG,
        ]

        def self.metadata : CommandInfo
          CommandInfo.new(
            name: NAME,
            description: DESCRIPTION,
            flags: FLAGS,
            positional_args: POSITIONAL_ARGS,
            positional_choices: POSITIONAL_CHOICES
          )
        end

        def run(args : Array(String))
          options, list_targets, json_output = parse_options(args)

          # Quiet logger so --json emits only the final JSON document. Human
          # --list-targets and --dry-run output is routed around Logger below.
          Logger.quiet = true if json_output
          Runner.json_mode = true if json_output

          if list_targets
            print_targets(options.env, json: json_output)
            return
          end

          # --dry-run + --json: return the planned ops as a JSON array and
          # exit without actually deploying. Schema per issue #356:
          #   [{target, action: "create"|"update"|"delete"|"command", path, source, destination}]
          if json_output && options.dry_run == true
            begin
              ops = Services::Deployer.new.plan(options)
              STDOUT.puts ops.to_json
            rescue ex : Hwaro::HwaroError
              STDOUT.puts ex.to_error_payload.to_json
              exit(ex.exit_code)
            rescue ex
              # Any plain exception that reaches us here is no longer a
              # config-load error (Models::Config.load raises HwaroError
              # directly) — keep the legacy minimal envelope and exit 1.
              STDOUT.puts({"status" => "error", "error" => {"message" => ex.message || "deploy plan failed"}}.to_json)
              exit(1)
            end
            return
          end

          if json_output
            # Real deploy with --json (no --dry-run) returns a per-target
            # summary. Schema per issue #374:
            #   {"status": "ok"|"error",
            #    "targets": [{"name","status","created","updated",
            #                 "deleted","duration_ms","error"?}]}
            # Config-load errors bubble up here as HwaroError and become a
            # top-level error payload (shape unchanged from #356).
            results = begin
              Services::Deployer.new.deploy_structured(options)
            rescue ex : Hwaro::HwaroError
              STDOUT.puts ex.to_error_payload.to_json
              exit(ex.exit_code)
            rescue ex
              STDOUT.puts({"status" => "error", "error" => {"message" => ex.message || "deploy failed"}}.to_json)
              exit(1)
            end

            overall = results.all? { |r| r.status == "ok" } ? "ok" : "error"
            payload = {"status" => overall, "targets" => results}
            STDOUT.puts payload.to_json
            exit(overall == "ok" ? 0 : worst_exit_for(results))
          end

          # Deployer#run raises Hwaro::HwaroError on failure; the Runner
          # catches it and emits the classified `Error [HWARO_E_XXX]: …`
          # line with the right exit code. A successful return is a
          # no-op — the Runner exits 0 at the end of `run` automatically.
          Services::Deployer.new.run(options)
        end

        # Pick the most severe exit code across failing targets so CI can
        # branch on whether a partial failure was config- vs upload-related.
        # Numerically higher exit codes win (HWARO_E_NETWORK=7 beats
        # HWARO_E_CONFIG=3). Falls back to EXIT_GENERIC (1) when there is
        # no classified error (shouldn't happen in practice).
        private def worst_exit_for(results : Array(Services::Deployer::DeployResult)) : Int32
          worst = Hwaro::Errors::EXIT_GENERIC
          results.each do |r|
            next if r.status == "ok"
            if err = r.error
              code = err["code"]?
              exit_code = code ? Hwaro::Errors.exit_for(code) : Hwaro::Errors::EXIT_GENERIC
              worst = exit_code if exit_code > worst
            end
          end
          worst
        end

        def parse_options(args : Array(String)) : {Config::Options::DeployOptions, Bool, Bool}
          source_dir = nil.as(String?)
          dry_run = nil.as(Bool?)
          confirm = nil.as(Bool?)
          force = nil.as(Bool?)
          max_deletes = nil.as(Int32?)
          list_targets = false
          json_output = false
          env_name = ENV["HWARO_ENV"]? || nil

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro deploy [options] [target ...]"
            parser.on("-s DIR", "--source DIR", "Source directory to deploy (default: deployment.source_dir or public)") { |dir| source_dir = dir }
            parser.on("--dry-run", "Show planned changes without writing") { dry_run = true }
            parser.on("--confirm", "Ask for confirmation before deploying") { confirm = true }
            parser.on("--force", "Force upload/copy (ignore file comparisons)") { force = true }
            parser.on("--max-deletes N", "Maximum number of deletes (default: deployment.maxDeletes or 256, -1 disables)") { |n| max_deletes = n.to_i }
            parser.on("--list-targets", "List configured deployment targets and exit") { list_targets = true }
            CLI.register_flag(parser, JSON_FLAG) { |_| json_output = true }
            CLI.register_flag(parser, ENV_FLAG) { |v| env_name = v }
            CLI.register_flag(parser, QUIET_FLAG) { |_| Logger.quiet = true }
            CLI.register_flag(parser, HELP_FLAG) do |_|
              Logger.info parser.to_s
              hint = configured_targets_hint(env_name)
              Logger.info hint unless hint.empty?
              exit
            end
          end

          targets = args.dup

          {
            Config::Options::DeployOptions.new(
              source_dir: source_dir,
              targets: targets,
              dry_run: dry_run,
              confirm: confirm,
              force: force,
              max_deletes: max_deletes,
              env: env_name,
            ),
            list_targets,
            json_output,
          }
        end

        private def print_targets(env : String? = nil, json : Bool = false)
          config = begin
            Models::Config.load(env: env)
          rescue ex : Hwaro::HwaroError
            if json
              STDOUT.puts ex.to_error_payload.to_json
            else
              Logger.error "Error [#{ex.code}]: #{ex.message}"
            end
            exit(ex.exit_code)
          end

          deployment = config.deployment

          if json
            mapped = deployment.targets.map do |t|
              {
                name:    t.name,
                url:     t.url,
                command: t.command,
              }
            end
            STDOUT.puts mapped.to_json
            return
          end

          if deployment.targets.empty?
            Logger.info "No deployment targets configured."
            return
          end

          Logger.info "Deployment targets:"
          deployment.targets.each do |t|
            Logger.info "  #{t.name.ljust(16)} #{format_target_destination(t)}"
          end
        end

        # Builds the "Configured targets" hint appended to `--help` output.
        # Returns an empty string when no `config.toml` is present so help stays
        # unchanged outside of project directories. Parsing failures surface a
        # friendly note instead of aborting `--help`.
        def configured_targets_hint(env : String?, config_path : String = "config.toml") : String
          return "" unless File.exists?(config_path)

          begin
            config = Models::Config.load(config_path, env: env)
          rescue ex
            return "\nConfigured targets: (could not read #{config_path}: #{ex.message})"
          end

          targets = config.deployment.targets
          if targets.empty?
            return "\nConfigured targets: (none defined in #{config_path})"
          end

          String.build do |str|
            str << "\nConfigured targets (from " << config_path << "):\n"
            targets.each do |t|
              str << "  " << t.name.ljust(16) << ' ' << format_target_destination(t) << '\n'
            end
          end
        end

        # Render the most informative destination string for a deployment target.
        private def format_target_destination(target : Models::DeploymentTarget) : String
          url = target.url.empty? ? "(no url)" : target.url
          extra = target.command ? " (command)" : ""
          "#{url}#{extra}"
        end
      end
    end
  end
end
