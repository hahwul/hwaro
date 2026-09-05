require "../../metadata"
require "../../../utils/errors"
require "../../../utils/file_safe"
require "../../../utils/logger"

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

            if File.exists?(filename) && !force
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_IO,
                message: "#{filename} already exists",
                hint: "Pass --force to overwrite it, -o PATH to write elsewhere, or --stdout to print it.",
              )
            end

            dir = File.dirname(filename)
            Hwaro::Utils::FileSafe.mkdir_p(dir) unless Dir.exists?(dir)
            File.write(filename, content)
            Logger.outcome("created", filename)
          end
        end
      end
    end
  end
end
