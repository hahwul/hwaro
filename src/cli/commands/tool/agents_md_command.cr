require "option_parser"
require "../../metadata"
require "../../../utils/logger"
require "../../../services/defaults/agents_md"

module Hwaro
  module CLI
    module Commands
      module Tool
        class AgentsMdCommand
          # Single source of truth for command metadata
          NAME               = "agents-md"
          DESCRIPTION        = "Generate or update AGENTS.md file"
          POSITIONAL_ARGS    = [] of String
          POSITIONAL_CHOICES = [] of String

          FLAGS = [
            FlagInfo.new(
              short: nil,
              long: "--remote",
              description: "Generate lightweight version with links to online docs"
            ),
            FlagInfo.new(
              short: nil,
              long: "--local",
              description: "Generate full embedded reference (default)"
            ),
            FlagInfo.new(
              short: nil,
              long: "--write",
              description: "Write to AGENTS.md file instead of stdout"
            ),
            FlagInfo.new(
              short: "-f",
              long: "--force",
              description: "Overwrite existing file without confirmation"
            ),
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
            remote = false
            write = false
            force = false

            OptionParser.parse(args) do |parser|
              parser.banner = "Usage: hwaro tool agents-md [options]"
              parser.on("--remote", "Generate lightweight version with links to online docs") { remote = true }
              parser.on("--local", "Generate full embedded reference (default)") { remote = false }
              parser.on("--write", "Write to AGENTS.md file instead of stdout") { write = true }
              parser.on("-f", "--force", "Overwrite existing file without confirmation") { force = true }
              CLI.register_flag(parser, HELP_FLAG) do |_|
                Logger.info parser.to_s
                exit
              end
            end

            content = if remote
                        Services::Defaults::AgentsMd.remote_content
                      else
                        Services::Defaults::AgentsMd.content
                      end

            if write
              filename = "AGENTS.md"
              if File.exists?(filename) && !force
                print "AGENTS.md already exists. Overwrite? [y/N] "
                answer = gets
                unless answer && answer.strip.downcase == "y"
                  Logger.info "Aborted."
                  exit
                end
              end

              File.write(filename, content)
              mode_name = remote ? "remote" : "local"
              Logger.success "Generated AGENTS.md (#{mode_name} mode)"
            else
              puts content
            end
          end
        end
      end
    end
  end
end
