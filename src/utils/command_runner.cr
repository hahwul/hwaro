# Command runner utility for executing user-defined hooks
#
# Provides functionality to execute shell commands for build hooks.
# Supports running multiple commands sequentially with proper error handling.

require "./logger"

module Hwaro
  module Utils
    class CommandRunner
      # Result of a command execution
      struct Result
        property success : Bool
        property output : String
        property error : String
        property exit_code : Int32

        def initialize(@success : Bool, @output : String, @error : String, @exit_code : Int32)
        end
      end

      # The command line to hand `Process` with `shell: true`. That is
      # `sh -c` on POSIX but a bare CreateProcess on Windows: no `&&`, pipes
      # or redirects, and no `.cmd` shims (`npm`, `npx`). Wrap it in cmd.exe
      # there, the way Node's `shell: true` does (`/s` strips the outer
      # quotes, `/d` skips AutoRun).
      def self.shell_command(command : String) : String
        {% if flag?(:windows) %}
          %(cmd.exe /d /s /c "#{command}")
        {% else %}
          command
        {% end %}
      end

      # Execute a single command and return the result
      def self.run(command : String, working_dir : String? = nil) : Result
        stdout = IO::Memory.new
        stderr = IO::Memory.new

        process_args = {
          command: shell_command(command),
          shell:   true,
          output:  stdout,
          error:   stderr,
          chdir:   working_dir,
        }

        status = Process.run(**process_args)

        Result.new(
          success: status.success?,
          output: stdout.to_s,
          error: stderr.to_s,
          exit_code: status.exit_code
        )
      end

      # Execute multiple commands sequentially
      # Returns true if all commands succeed, false otherwise
      def self.run_all(commands : Array(String), working_dir : String? = nil, label : String = "hook") : Bool
        return true if commands.empty?

        commands.each_with_index do |command, index|
          Logger.action(:Running, "#{label} [#{index + 1}/#{commands.size}]: #{command}")

          result = run(command, working_dir)

          unless result.output.empty?
            result.output.each_line do |line|
              Logger.info "  #{line}"
            end
          end

          unless result.success
            Logger.error "Command failed with exit code #{result.exit_code}: #{command}"
            unless result.error.empty?
              result.error.each_line do |line|
                Logger.error "  #{line}"
              end
            end
            return false
          end
        end

        true
      end

      # Execute pre-build hooks
      def self.run_pre_hooks(commands : Array(String)) : Bool
        run_hooks(commands, "pre-build")
      end

      # Execute post-build hooks
      def self.run_post_hooks(commands : Array(String)) : Bool
        run_hooks(commands, "post-build")
      end

      private def self.run_hooks(commands : Array(String), phase : String) : Bool
        return true if commands.empty?

        Logger.info "Running #{phase} hooks..."
        success = run_all(commands, label: phase)

        if success
          Logger.success "#{phase.capitalize} hooks completed successfully."
        else
          Logger.error "#{phase.capitalize} hooks failed."
        end

        success
      end
    end
  end
end
