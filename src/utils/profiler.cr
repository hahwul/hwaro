# Build Profiler utility for timing build phases
#
# Provides detailed timing information for each build phase
# when the --profile flag is enabled.

require "colorize"

module Hwaro
  class Profiler
    # Represents timing for a single phase
    struct PhaseTime
      property phase : String
      property duration_ms : Float64

      def initialize(@phase : String, @duration_ms : Float64 = 0.0)
      end
    end

    @enabled : Bool
    @phases : Array(PhaseTime)
    @current_phase : String?
    @phase_start : Time::Instant?
    @total_start : Time::Instant?

    def initialize(@enabled : Bool = false)
      @phases = [] of PhaseTime
      @current_phase = nil
      @phase_start = nil
      @total_start = nil
    end

    def enabled? : Bool
      @enabled
    end

    # Start the overall profiling
    def start
      return unless @enabled
      @total_start = Time.instant
    end

    # Start timing a phase
    def start_phase(phase : String)
      return unless @enabled
      @current_phase = phase
      @phase_start = Time.instant
    end

    # End timing for the current phase
    def end_phase
      return unless @enabled

      phase_start = @phase_start
      current_phase = @current_phase
      return unless phase_start && current_phase

      duration = (Time.instant - phase_start).total_milliseconds
      @phases << PhaseTime.new(current_phase, duration)
      @current_phase = nil
      @phase_start = nil
    end

    # Get total elapsed time
    def total_elapsed : Float64
      if start = @total_start
        (Time.instant - start).total_milliseconds
      else
        0.0
      end
    end

    # Print the profiling report
    def report(io : IO = STDOUT)
      return unless @enabled
      return if @phases.empty?

      io.puts ""
      io.puts "Build Profile".colorize(:cyan).bold
      io.puts "─" * 50

      total = @phases.sum(&.duration_ms)
      max_name_len = @phases.map(&.phase.size).max

      @phases.each do |phase|
        percent = if total > 0
                    (phase.duration_ms / total * 100).round(1)
                  else
                    0.0
                  end

        name = phase.phase.ljust(max_name_len + 2)
        time_str = format_time(phase.duration_ms).rjust(10)
        percent_str = "(#{percent}%)".rjust(8)

        bar = render_bar(percent, 20)

        io.puts "  #{name} #{time_str} #{percent_str} #{bar}"
      end

      io.puts "─" * 50
      io.puts "  #{"Total".ljust(max_name_len + 2)} #{format_time(total).rjust(10)}"
      io.puts ""
    end

    # Format time in appropriate units
    private def format_time(ms : Float64) : String
      if ms < 1
        "#{(ms * 1000).round(2)}µs"
      elsif ms < 1000
        "#{ms.round(2)}ms"
      else
        "#{(ms / 1000).round(2)}s"
      end
    end

    # Render a simple bar chart
    private def render_bar(percent : Float64, width : Int32) : String
      filled = (percent / 100.0 * width).to_i
      filled = [filled, width].min
      bar = "█" * filled + "░" * (width - filled)
      bar.colorize(:blue).to_s
    end
  end
end
