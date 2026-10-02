require "../../metadata"
require "../../../utils/errors"
require "../../../utils/file_safe"
require "../../../utils/logger"
require "../../../utils/path_utils"

module Hwaro
  module CLI
    module Commands
      module Tool
        # Shared by the `tool platform` / `tool ci` generators: the flag set
        # and the "print it or write it, refusing to clobber" tail. Keeping
        # one copy means the two commands cannot disagree on how `--force`,
        # `-o` and `--stdout` behave.
        module FileGenerator
          extend self

          FLAGS = [
            FlagInfo.new(
              short: "-o",
              long: "--output",
              description: "Output file path (default: auto-detected)",
              takes_value: true,
              value_hint: "PATH"
            ),
            FlagInfo.new(
              short: nil,
              long: "--stdout",
              description: "Print to stdout instead of writing file"
            ),
            FlagInfo.new(
              short: "-f",
              long: "--force",
              description: "Overwrite existing file without warning"
            ),
            HELP_FLAG,
          ]

          # Print `content` (`stdout_mode`) or write it to `filename`,
          # refusing to overwrite an existing file unless `force`.
          def emit(filename : String, content : String, stdout_mode : Bool, force : Bool) : Nil
            if stdout_mode
              puts content
              return
            end

            if filename.strip.empty?
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_USAGE,
                message: "--output must not be empty",
                hint: "Pass a file path to -o/--output, or omit it to use the default path.",
              )
            end

            if Dir.exists?(filename)
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "#{filename} is a directory",
                hint: "Pass a file path to -o/--output, e.g. -o #{File.join(filename, "deploy.yml")}.",
              )
            end

            # A path the user named inside the project must not be redirected
            # out of it by a symlink (the leaf or a parent directory) — the
            # same rule `tool agents-md --write` applies. A checked-out
            # `netlify.toml -> ~/.bashrc` link was written straight through,
            # with no prompt when the link dangled and under `--force`
            # otherwise. An explicit `-o` outside the project is honoured.
            if names_project_path?(filename) && !link_target_within_project?(filename)
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "Cannot write #{filename} through a symlink that resolves outside the project.",
                hint: "Point the symlink at a file inside the project, remove it, or pass -o with the real destination.",
              )
            end

            if File.exists?(filename) && !force
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "#{filename} already exists",
                hint: "Pass --force to overwrite it, -o PATH to write elsewhere, or --stdout to print it.",
              )
            end

            begin
              dir = File.dirname(filename)
              Hwaro::Utils::FileSafe.mkdir_p(dir) unless Dir.exists?(dir)
              File.write(filename, content)
            rescue ex : File::Error | IO::Error
              # Classified like the refusal above instead of escaping as an
              # unhandled exception (`Error: Error opening file …`, exit 1).
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "Could not write #{filename}: #{ex.message}",
                hint: "Check that the path is writable, or pass --stdout to print the file instead.",
              )
            end
            Logger.outcome("created", filename)
          end

          # Whether writing through `path` lands inside the current project.
          # The project's own symlink rule: follow links resolving within it
          # (the common `AGENTS.md -> CLAUDE.md`), refuse links resolving
          # outside. A dangling link would create its target, so the chain is
          # followed hop by hop to where `File.write` would create the file;
          # a loop resolves nowhere and is refused.
          def link_target_within_project?(path : String) : Bool
            target = File.expand_path(path)
            40.times do
              return within_project?(target) unless File.symlink?(target)
              link = File.readlink?(target)
              return false unless link
              target = File.expand_path(link, File.dirname(target))
            end
            false
          end

          private def within_project?(path : String) : Bool
            root = Hwaro::Utils::PathUtils.resolved_real_path(Dir.current)
            resolved = Hwaro::Utils::PathUtils.resolved_real_path(path)
            Hwaro::Utils::PathUtils.within?(resolved, root)
          end

          # Whether `path` names a location in the project — the case where a
          # symlink must not redirect the write out of it. Judged by the
          # spelling against both spellings of the project root (`Dir.current`
          # may be reached through a symlink such as /tmp -> /private/tmp, so
          # `/private/tmp/…/proj/x` is as much "in the project" as
          # `/tmp/…/proj/x`), and by the resolved parent directory. A
          # symlinked parent that leaves the project (`.github -> /elsewhere`)
          # still counts through its in-project spelling.
          private def names_project_path?(path : String) : Bool
            expanded = File.expand_path(path)
            lexical_root = File.expand_path(Dir.current)
            real_root = Hwaro::Utils::PathUtils.resolved_real_path(Dir.current)
            real_parent = Hwaro::Utils::PathUtils.resolved_real_path(File.dirname(expanded))
            Hwaro::Utils::PathUtils.within?(expanded, lexical_root) ||
              Hwaro::Utils::PathUtils.within?(expanded, real_root) ||
              Hwaro::Utils::PathUtils.within?(real_parent, real_root)
          end
        end
      end
    end
  end
end
