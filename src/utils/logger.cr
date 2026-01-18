# Logger utility for consistent output formatting
#
# Provides colored console output with different log levels
# and action formatting for build operations.

require "colorize"

module Hwaro
  class Logger
    @@io : IO = STDOUT

    # Log levels for filtering
    enum Level
      Debug
      Info
      Warn
      Error
    end

    @@level : Level = Level::Info

    def self.io=(io : IO)
      @@io = io
    end

    def self.level=(level : Level)
      @@level = level
    end

    def self.level : Level
      @@level
    end

    def self.debug(message : String)
      return if @@level > Level::Debug
      @@io.puts "[DEBUG] #{message}".colorize(:light_gray)
    end

    def self.info(message : String)
      return if @@level > Level::Info
      @@io.puts message
    end

    def self.error(message : String)
      @@io.puts message.colorize(:red)
    end

    def self.warn(message : String)
      return if @@level > Level::Warn
      @@io.puts message.colorize(:yellow)
    end

    def self.success(message : String)
      @@io.puts message.colorize(:green)
    end

    def self.action(label : String | Symbol, message : String, color : Symbol = :green)
      label_s = label.to_s.rjust(12)
      @@io.puts "#{label_s.colorize(color).bold}  #{message}"
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
      percent = (current.to_f / total * 100).round(1)
      bar_width = 30
      filled = (current.to_f / total * bar_width).to_i
      bar = "█" * filled + "░" * (bar_width - filled)
      @@io.print "\r#{prefix}[#{bar}] #{percent}% (#{current}/#{total})"
      @@io.puts if current >= total
    end
  end
end
