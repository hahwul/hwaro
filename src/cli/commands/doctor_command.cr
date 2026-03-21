# Doctor command - Top-level alias for `hwaro tool doctor`
#
# Diagnoses config and content issues.
# Usage:
#   hwaro doctor [options]
#
# This is a convenience alias; `hwaro tool doctor` also works.

require "./tool/doctor_command"

module Hwaro
  module CLI
    module Commands
      class DoctorCommand
        NAME        = "doctor"
        DESCRIPTION = Tool::DoctorCommand::DESCRIPTION

        def self.metadata : CommandInfo
          # Reuse flags from the underlying Tool::DoctorCommand
          CommandInfo.new(
            name: NAME,
            description: DESCRIPTION,
            flags: Tool::DoctorCommand::FLAGS,
            positional_args: Tool::DoctorCommand::POSITIONAL_ARGS,
            positional_choices: Tool::DoctorCommand::POSITIONAL_CHOICES
          )
        end

        def run(args : Array(String))
          Tool::DoctorCommand.new.run(args)
        end
      end
    end
  end
end
