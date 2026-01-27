require "option_parser"
require "../../config/options/deploy_options"
require "../../models/config"
require "../../services/deployer"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      class DeployCommand
        def run(args : Array(String))
          options, list_targets = parse_options(args)
          if list_targets
            print_targets
            return
          end

          ok = Services::Deployer.new.run(options)
          exit(1) unless ok
        end

        private def parse_options(args : Array(String)) : {Config::Options::DeployOptions, Bool}
          source_dir = nil.as(String?)
          dry_run = nil.as(Bool?)
          confirm = nil.as(Bool?)
          force = nil.as(Bool?)
          max_deletes = nil.as(Int32?)
          list_targets = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: hwaro deploy [options] [target ...]"
            parser.on("-s DIR", "--source DIR", "Source directory to deploy (default: deployment.source_dir or public)") { |dir| source_dir = dir }
            parser.on("--dry-run", "Show planned changes without writing") { dry_run = true }
            parser.on("--confirm", "Ask for confirmation before deploying") { confirm = true }
            parser.on("--force", "Force upload/copy (ignore file comparisons)") { force = true }
            parser.on("--max-deletes N", "Maximum number of deletes (default: deployment.maxDeletes or 256, -1 disables)") { |n| max_deletes = n.to_i }
            parser.on("--list-targets", "List configured deployment targets and exit") { list_targets = true }
            parser.on("-h", "--help", "Show this help") { Logger.info parser.to_s; exit }
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
            ),
            list_targets,
          }
        end

        private def print_targets
          config = Models::Config.load
          deployment = config.deployment
          if deployment.targets.empty?
            Logger.info "No deployment targets configured."
            return
          end

          Logger.info "Deployment targets:"
          deployment.targets.each do |t|
            url = t.url.empty? ? "(no url)" : t.url
            extra = t.command ? " (command)" : ""
            Logger.info "  #{t.name.ljust(16)} #{url}#{extra}"
          end
        end
      end
    end
  end
end

