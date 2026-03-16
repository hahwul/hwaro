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

    # Represents per-template profiling data
    struct TemplateProfile
      property template : String
      property count : Int32
      property total_bytes : Int64
      property total_time_ms : Float64

      def initialize(@template : String, @count : Int32 = 0, @total_bytes : Int64 = 0_i64, @total_time_ms : Float64 = 0.0)
      end
    end

    @enabled : Bool
    @phases : Array(PhaseTime)
    @current_phase : String?
    @phase_start : Time::Instant?
    @total_start : Time::Instant?
    @template_profiles : Hash(String, TemplateProfile)
    @template_mutex : Mutex

    def initialize(@enabled : Bool = false)
      @phases = [] of PhaseTime
      @current_phase = nil
      @phase_start = nil
      @total_start = nil
      @template_profiles = {} of String => TemplateProfile
      @template_mutex = Mutex.new
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
      max_name_len = @phases.map(&.phase.size).max? || 0

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

    # Record per-template profiling data
    def record_template(template : String, bytes : Int64, time_ms : Float64)
      return unless @enabled
      @template_mutex.synchronize do
        profile = @template_profiles[template]? || TemplateProfile.new(template)
        @template_profiles[template] = TemplateProfile.new(
          template: template,
          count: profile.count + 1,
          total_bytes: profile.total_bytes + bytes,
          total_time_ms: profile.total_time_ms + time_ms,
        )
      end
    end

    # Print the per-template profiling report
    def template_report(io : IO = STDOUT)
      return unless @enabled
      return if @template_profiles.empty?

      sorted = @template_profiles.values.sort_by { |tp| -tp.total_time_ms }

      # Calculate column widths
      max_name_len = sorted.map { |tp| tp.template.size }.max
      max_name_len = {max_name_len, 8}.max # minimum "Template" header width
      header_width = max_name_len

      io.puts ""
      io.puts "Template Profile".colorize(:cyan).bold

      # Header
      io.puts "#{"Template".ljust(header_width)} | Count | #{" Bytes".rjust(10)} | #{"Time".rjust(10)}"
      io.puts "#{"-" * header_width}-+-------+#{"-" * 12}+#{"-" * 11}"

      # Rows
      sorted.each do |tp|
        name = tp.template.ljust(header_width)
        count = tp.count.to_s.rjust(5)
        bytes = format_bytes(tp.total_bytes).rjust(10)
        time = format_time(tp.total_time_ms).rjust(10)
        io.puts "#{name} | #{count} | #{bytes} | #{time}"
      end

      # Total row
      total_time = sorted.sum(&.total_time_ms)
      io.puts "#{" " * header_width}   #{" " * 5}   #{" " * 10}  #{"─" * 10}"
      io.puts "#{" " * header_width}    Total#{" " * (10 + 5)} #{format_time(total_time).rjust(10)}"
      io.puts ""
    end

    # Format byte sizes in human-readable form
    private def format_bytes(bytes : Int64) : String
      if bytes < 1024
        "#{bytes}B"
      elsif bytes < 1024 * 1024
        "#{"%.2f" % (bytes / 1024.0)}K"
      else
        "#{"%.2f" % (bytes / (1024.0 * 1024.0))}M"
      end
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
