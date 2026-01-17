require "colorize"

module Hwaro
  class Logger
    @@io : IO = STDOUT

    def self.io=(io : IO)
      @@io = io
    end

    def self.info(message : String)
      @@io.puts message
    end

    def self.error(message : String)
      @@io.puts message.colorize(:red)
    end

    def self.warn(message : String)
      @@io.puts message.colorize(:yellow)
    end

    def self.success(message : String)
      @@io.puts message.colorize(:green)
    end

    def self.action(label : String | Symbol, message : String, color : Symbol = :green)
      label_s = label.to_s.rjust(12)
      @@io.puts "#{label_s.colorize(color).bold}  #{message}"
    end
  end
end
