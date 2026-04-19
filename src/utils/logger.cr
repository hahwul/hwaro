# Logger utility for consistent output formatting
#
# Provides colored console output with different log levels
# and action formatting for build operations.
#
# Color output is automatically disabled when:
#   * `NO_COLOR` is set to a non-empty value (see https://no-color.org), or
#   * `STDOUT` is not a TTY (e.g. piping to a file or `cat`), or
#   * `Logger.color_enabled=` has been explicitly set to false.
#
# Quiet mode (`Logger.quiet=`) suppresses `info`, `action`, `success`, and
# `progress` output while still emitting `warn` and `error`, which are
# additionally routed to STDERR for easy redirection.

require "colorize"

module Hwaro
  class Logger
    @@io : IO = STDOUT
    @@err_io : IO = STDERR

    # Log levels for filtering
    enum Level
      Debug
      Info
      Warn
      Error
    end

    @@level : Level = Level::Info
    @@quiet : Bool = false
    @@color_enabled : Bool? = nil

    # Setting `io` also redirects error/warn output to the same IO, which
    # keeps existing test helpers (that capture a single IO) working and
    # makes manual redirection straightforward. Use `err_io=` afterwards to
    # split streams explicitly.
    def self.io=(io : IO)
      @@io = io
      @@err_io = io
    end

    def self.io : IO
      @@io
    end

    def self.err_io=(io : IO)
      @@err_io = io
    end

    def self.err_io : IO
      @@err_io
    end

    def self.level=(level : Level)
      @@level = level
    end

    def self.level : Level
      @@level
    end

    def self.quiet=(value : Bool)
      @@quiet = value
    end

    def self.quiet? : Bool
      @@quiet
    end

    # Explicit override. Pass `nil` to restore auto-detection.
    def self.color_enabled=(value : Bool?)
      @@color_enabled = value
    end

    # Auto-detect unless explicitly set. Disabled when `NO_COLOR` env var
    # is set to any non-empty value, or when STDOUT is not a TTY.
    def self.color_enabled? : Bool
      unless (override = @@color_enabled).nil?
        return override
      end
      return false if ENV.has_key?("NO_COLOR") && !ENV["NO_COLOR"].empty?
      STDOUT.tty?
    end

    def self.debug(message : String)
      return if @@level > Level::Debug
      return if @@quiet
      @@io.puts colorize("[DEBUG] #{message}", :light_gray)
    end

    def self.info(message : String)
      return if @@level > Level::Info
      return if @@quiet
      @@io.puts message
    end

    def self.error(message : String)
      @@err_io.puts colorize(message, :red)
    end

    def self.warn(message : String)
      return if @@level > Level::Warn
      @@err_io.puts colorize("[WARN] #{message}", :yellow)
    end

    def self.success(message : String)
      return if @@quiet
      @@io.puts colorize(message, :green)
    end

    def self.action(label : String | Symbol, message : String, color : Symbol = :green)
      return if @@quiet
      label_s = label.to_s.rjust(12)
      if color_enabled?
        @@io.puts "#{label_s.colorize(color).bold}  #{message}"
      else
        @@io.puts "#{label_s}  #{message}"
      end
    end

    # Performance timing helper
    def self.timed(message : String, &block)
      start = Time.instant
      result = yield
      elapsed = Time.instant - start
      info "#{message} (#{elapsed.total_milliseconds.round(2)}ms)"
      result
    end

    # Progress indicator for long operations
    def self.progress(current : Int32, total : Int32, prefix : String = "")
      return if total <= 0
      return if @@quiet
      percent = (current.to_f / total * 100).round(1)
      bar_width = 30
      filled = (current.to_f / total * bar_width).to_i
      bar = "█" * filled + "░" * (bar_width - filled)
      @@io.print "\r#{prefix}[#{bar}] #{percent}% (#{current}/#{total})"
      @@io.puts if current >= total
    end

    # Colorize helper that respects `color_enabled?`. Returns the raw string
    # (no ANSI escapes) when color is disabled, so output stays clean for
    # scripts, CI, and AI agents.
    private def self.colorize(message : String, color : Symbol) : String
      return message unless color_enabled?
      message.colorize(color).to_s
    end
  end
end
