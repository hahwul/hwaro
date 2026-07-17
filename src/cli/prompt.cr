require "../utils/logger"

module Hwaro
  module CLI
    # Small, reusable line-prompt toolkit for interactive commands.
    #
    # Output goes through `Logger.io` (the same redirectable IO the rest of the
    # CLI prints to) and reads from an injectable input IO that defaults to
    # `STDIN`. Tests drive both ends without a real terminal:
    #
    #     Logger.io = IO::Memory.new
    #     Prompt.input = IO::Memory.new("My Title\n\n")
    #
    # Every prompt is styled with the shared "ember" identity (the `◇` prompt
    # glyph + a dim default hint) and degrades to plain text under
    # `NO_COLOR` / non-TTY, so piped or captured output stays clean.
    #
    # A bare EOF (Ctrl-D) on any prompt returns `nil` — callers treat that as
    # "cancelled" rather than looping forever on a closed stream.
    module Prompt
      @@input : IO = STDIN

      # Inject the input stream (specs). Pass `STDIN` to restore the default.
      def self.input=(io : IO) : Nil
        @@input = io
      end

      def self.input : IO
        @@input
      end

      # True only when both ends are a real terminal. Commands gate interactive
      # flows on this so pipes, CI, and agents fall back to non-interactive
      # behaviour instead of blocking on a `gets` that will never arrive.
      def self.interactive? : Bool
        STDIN.tty? && STDOUT.tty?
      end

      # Ask a free-text question. Returns the trimmed answer, `default` when the
      # user just presses Enter, or `nil` on EOF (Ctrl-D).
      def self.ask(label : String, default : String? = nil) : String?
        emit_label(label, default)
        line = @@input.gets
        return if line.nil?
        answer = line.strip
        answer.empty? ? default : answer
      end

      # Ask until a non-empty answer is given. Returns `nil` on EOF so the caller
      # can cancel cleanly instead of spinning on a closed stream.
      def self.ask_required(label : String) : String?
        loop do
          emit_label(label, nil)
          line = @@input.gets
          return if line.nil?
          answer = line.strip
          return answer unless answer.empty?
          Logger.warn "  required — please enter a value."
        end
      end

      # Yes/no question. `default` decides the Enter behaviour and which letter
      # is capitalised in the `[Y/n]` / `[y/N]` hint. Returns `nil` on EOF.
      def self.confirm?(label : String, default : Bool = false) : Bool?
        suffix = default ? "[Y/n]" : "[y/N]"
        Logger.io.print "  #{Logger.glyph(:prompt)} #{Logger.paint(label, Logger::Role::Plain, bold: true)} #{Logger.paint(suffix, Logger::Role::Dim)} "
        Logger.io.flush
        line = @@input.gets
        return if line.nil?
        answer = line.strip.downcase
        return default if answer.empty?
        answer == "y" || answer == "yes"
      end

      # Numbered single-choice picker. Enter (or an out-of-the-way blank line)
      # returns `nil`, meaning "no selection" — callers use that for the
      # auto/default branch. Accepts either the 1-based index or an exact choice
      # string. Returns `nil` on EOF. Re-asks on an unrecognised entry.
      def self.select(label : String, choices : Array(String), skip_hint : String = "Enter to skip") : String?
        return if choices.empty?
        loop do
          Logger.io.puts "  #{Logger.glyph(:prompt)} #{Logger.paint(label, Logger::Role::Plain, bold: true)} #{Logger.paint("(#{skip_hint})", Logger::Role::Dim)}"
          choices.each_with_index do |choice, i|
            Logger.io.puts "      #{Logger.paint("#{i + 1})", Logger::Role::Dim)} #{choice}"
          end
          Logger.io.print "  #{Logger.paint("choice", Logger::Role::Dim)} "
          Logger.io.flush
          line = @@input.gets
          return if line.nil?
          answer = line.strip
          return if answer.empty?
          if (idx = answer.to_i?) && idx >= 1 && idx <= choices.size
            return choices[idx - 1]
          end
          if choices.includes?(answer)
            return answer
          end
          Logger.warn "  '#{answer}' is not one of the choices — enter a number 1-#{choices.size}, a name, or press Enter to skip."
        end
      end

      private def self.emit_label(label : String, default : String?) : Nil
        hint = (default && !default.empty?) ? " #{Logger.paint("[#{default}]", Logger::Role::Dim)}" : ""
        Logger.io.print "  #{Logger.glyph(:prompt)} #{Logger.paint(label, Logger::Role::Plain, bold: true)}#{hint} "
        Logger.io.flush
      end
    end
  end
end
