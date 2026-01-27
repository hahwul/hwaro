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

      # Execute a single command and return the result
      def self.run(command : String, working_dir : String? = nil, env : Hash(String, String)? = nil) : Result
        stdout = IO::Memory.new
        stderr = IO::Memory.new

        process_args = {
          command: command,
          shell:   true,
          output:  stdout,
          error:   stderr,
          chdir:   working_dir,
          env:     env,
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
      def self.run_all(commands : Array(String), working_dir : String? = nil, label : String = "hook", env : Hash(String, String)? = nil) : Bool
        return true if commands.empty?

        commands.each_with_index do |command, index|
          Logger.action(:Running, "#{label} [#{index + 1}/#{commands.size}]: #{command}")

          result = run(command, working_dir, env)

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
      def self.run_pre_hooks(commands : Array(String), working_dir : String? = nil, env : Hash(String, String)? = nil) : Bool
        return true if commands.empty?

        Logger.info "Running pre-build hooks..."
        success = run_all(commands, working_dir, "pre-build", env)

        if success
          Logger.success "Pre-build hooks completed successfully."
        else
          Logger.error "Pre-build hooks failed."
        end

        success
      end

      # Execute post-build hooks
      def self.run_post_hooks(commands : Array(String), working_dir : String? = nil, env : Hash(String, String)? = nil) : Bool
        return true if commands.empty?

        Logger.info "Running post-build hooks..."
        success = run_all(commands, working_dir, "post-build", env)

        if success
          Logger.success "Post-build hooks completed successfully."
        else
          Logger.error "Post-build hooks failed."
        end

        success
      end
    end
  end
end
