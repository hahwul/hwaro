require "option_parser"
require "../../metadata"
require "../../prompt"
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
              description: "Regenerate an existing file without confirmation (the Site-Specific Instructions section is still preserved)"
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
              parser.on("-f", "--force", "Regenerate an existing file without confirmation (the Site-Specific Instructions section is still preserved)") { force = true }
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
              existed = File.exists?(filename)
              existing = existed ? File.read(filename) : nil
              # Only promise preservation when the merge can actually deliver
              # it: an existing file without the marker heading gets a full
              # overwrite, and the prompt must say so instead of reassuring.
              # Uses the same line-anchored, fence-aware detection as the
              # merge itself so the prompt never promises what the merge
              # won't do.
              has_marker = existing ? !site_section_index(existing).nil? : false
              if existed && !force
                question = if has_marker
                             "AGENTS.md already exists. Regenerate it? (your Site-Specific Instructions are kept)"
                           else
                             "AGENTS.md already exists and has no '#{SITE_SECTION_MARKER}' heading — regenerating will replace it ENTIRELY. Continue?"
                           end
                # `confirm?` returns nil on EOF (piped/non-interactive stdin) —
                # treat that the same as "no" and abort without writing.
                unless Prompt.confirm?(question, default: false) == true
                  Logger.info "Aborted."
                  exit
                end
              end

              preserved = false
              if existing
                if existed && !has_marker
                  # `--force` skips the prompt above, so this loss warning is
                  # the only signal the non-interactive path gets.
                  Logger.warn "Existing AGENTS.md has no '#{SITE_SECTION_MARKER}' heading — replacing the whole file."
                end
                merged = merge_site_section(content, existing)
                preserved = merged != content
                content = merged
              end

              File.write(filename, content)
              mode_name = remote ? "remote" : "local"
              outcome_verb = existed ? "updated" : "created"
              summary = "AGENTS.md · #{mode_name} mode"
              summary += " · site-specific section preserved" if preserved
              Logger.outcome(outcome_verb, summary)
            else
              puts content
            end
          end

          # The generated document ends with a "Site-Specific Instructions"
          # section that explicitly invites the user to add their own rules.
          # Regenerating used to overwrite the whole file — destroying exactly
          # the content the template told them to write there. Carry the
          # existing file's section (heading included) into the fresh
          # template; a file without the marker falls back to a full rewrite
          # (announced above), as does a template variant without one. The
          # marker itself lives on the template service so the two can't
          # drift apart.
          SITE_SECTION_MARKER = Services::Defaults::AgentsMd::SITE_SECTION_MARKER

          # The heading only counts when it is a whole line on its own
          # (trailing blanks aside). A first-substring `index` let a mention
          # inside a code fence or mid-prose shift the merge point —
          # duplicating stale generated content or silently discarding user
          # sections above the real heading.
          # Up to three leading spaces still renders as the same ATX heading.
          MARKER_LINE_RE = /\A {0,3}#{Regex.escape(Services::Defaults::AgentsMd::SITE_SECTION_MARKER)}[ \t]*\z/
          FENCE_RE       = /\A {0,3}(`{3,}|~{3,})/

          private def merge_site_section(fresh : String, existing : String) : String
            existing_idx = site_section_index(existing)
            return fresh unless existing_idx
            fresh_idx = site_section_index(fresh)
            return fresh unless fresh_idx
            fresh[0...fresh_idx] + existing[existing_idx..]
          end

          # Char index of the real Site-Specific Instructions heading: the
          # FIRST line equal to the marker that is not inside a fenced code
          # block — deterministic, and identical to the old behavior for
          # normal files, where the heading occurs exactly once. When an
          # UNCLOSED fence swallowed the rest of the file, rescan ignoring
          # fences: preserving the user's section on malformed markdown beats
          # a full rewrite that silently discards it. (A marker inside a
          # properly closed fence stays a non-match — that's the quoted
          # example the fence tracking exists for.)
          private def site_section_index(text : String) : Int32?
            index, unterminated = scan_for_marker(text, fence_aware: true)
            return index if index
            return unless unterminated
            scan_for_marker(text, fence_aware: false)[0]
          end

          private def scan_for_marker(text : String, fence_aware : Bool) : {Int32?, Bool}
            offset = 0
            fence_delim : String? = nil
            text.each_line(chomp: false) do |raw_line|
              line = raw_line.chomp
              if delim = fence_delim
                if closing = line.match(FENCE_RE).try(&.[1])
                  fence_delim = nil if closing[0] == delim[0] && closing.size >= delim.size
                end
              elsif fence_aware && (opening = line.match(FENCE_RE).try(&.[1]))
                fence_delim = opening
              elsif line.matches?(MARKER_LINE_RE)
                return {offset, false}
              end
              offset += raw_line.size
            end
            {nil, !fence_delim.nil?}
          end
        end
      end
    end
  end
end
