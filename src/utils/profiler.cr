# Build Profiler utility for timing build phases
#
# Provides detailed timing information for each build phase
# when the --profile flag is enabled.

require "./logger"

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

    # Represents per-page Markdown rendering profiling data (the dominant cost inside Render phase)
    struct MarkdownProfile
      property path : String
      property count : Int32
      property total_bytes : Int64
      property total_time_ms : Float64

      def initialize(@path : String, @count : Int32 = 0, @total_bytes : Int64 = 0_i64, @total_time_ms : Float64 = 0.0)
      end
    end

    @enabled : Bool
    @phases : Array(PhaseTime)
    @current_phase : String?
    @phase_start : Time::Instant?
    @total_start : Time::Instant?
    @template_profiles : Hash(String, TemplateProfile)
    @template_mutex : Mutex
    @markdown_profiles : Hash(String, MarkdownProfile)
    @markdown_mutex : Mutex

    # Simple aggregate stats for expensive BeforeRender hooks
    struct AssetGenerationStats
      property name : String
      property generated : Int32
      property skipped : Int32
      property time_ms : Float64

      def initialize(@name, @generated = 0, @skipped = 0, @time_ms = 0.0)
      end
    end

    @asset_stats : Array(AssetGenerationStats)
    @asset_mutex : Mutex

    # General per-hook timing (D3 for #561)
    struct HookProfile
      property name : String
      property count : Int32
      property total_time_ms : Float64

      def initialize(@name, @count = 0, @total_time_ms = 0.0)
      end
    end

    @hook_profiles : Hash(String, HookProfile)
    @hook_mutex : Mutex

    def initialize(@enabled : Bool = false)
      @phases = [] of PhaseTime
      @current_phase = nil
      @phase_start = nil
      @total_start = nil
      @template_profiles = {} of String => TemplateProfile
      @template_mutex = Mutex.new
      @markdown_profiles = {} of String => MarkdownProfile
      @markdown_mutex = Mutex.new
      @asset_stats = [] of AssetGenerationStats
      @asset_mutex = Mutex.new
      @hook_profiles = {} of String => HookProfile
      @hook_mutex = Mutex.new
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
      io.puts Logger.paint("Build Profile", Logger::Role::Heading, bold: true)
      io.puts Logger.paint("─" * 50, Logger::Role::Dim)

      total = @phases.sum(&.duration_ms)
      max_name_len = @phases.max_of?(&.phase.size) || 0

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

      io.puts Logger.paint("─" * 50, Logger::Role::Dim)
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

    # Record per-page Markdown rendering profiling data.
    # This captures the dominant cost inside the Render phase (Markd + extensions + TOC + shortcode prep).
    def record_markdown(path : String, bytes : Int64, time_ms : Float64)
      return unless @enabled
      @markdown_mutex.synchronize do
        profile = @markdown_profiles[path]? || MarkdownProfile.new(path)
        @markdown_profiles[path] = MarkdownProfile.new(
          path: path,
          count: profile.count + 1,
          total_bytes: profile.total_bytes + bytes,
          total_time_ms: profile.total_time_ms + time_ms,
        )
      end
    end

    # Record timing for expensive asset generation hooks (OG images, image resizing).
    # These are the #1 cost on many sites even with aggressive caching.
    def record_asset_generation(name : String, generated : Int32, skipped : Int32, time_ms : Float64)
      return unless @enabled
      @asset_mutex.synchronize do
        @asset_stats << AssetGenerationStats.new(name, generated, skipped, time_ms)
      end
    end

    # Record timing for any lifecycle hook (general per-hook profiling, #561).
    # Called automatically from Lifecycle::Manager#trigger when profiler is enabled.
    def record_hook(name : String, time_ms : Float64)
      return unless @enabled
      @hook_mutex.synchronize do
        profile = @hook_profiles[name]? || HookProfile.new(name)
        @hook_profiles[name] = HookProfile.new(
          name: name,
          count: profile.count + 1,
          total_time_ms: profile.total_time_ms + time_ms,
        )
      end
    end

    # Print the per-template profiling report
    def template_report(io : IO = STDOUT)
      return unless @enabled
      return if @template_profiles.empty?

      sorted = @template_profiles.values.sort_by! { |tp| -tp.total_time_ms }

      # Calculate column widths
      max_name_len = sorted.max_of(&.template.size)
      max_name_len = {max_name_len, 8}.max # minimum "Template" header width
      header_width = max_name_len

      io.puts ""
      io.puts Logger.paint("Template Profile", Logger::Role::Heading, bold: true)

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

    # Print the per-page Markdown rendering report (sorted by total time, top consumers first)
    def markdown_report(io : IO = STDOUT)
      return unless @enabled
      return if @markdown_profiles.empty?

      sorted = @markdown_profiles.values.sort_by! { |mp| -mp.total_time_ms }

      max_name_len = sorted.max_of(&.path.size)
      max_name_len = {max_name_len, 12}.max
      header_width = max_name_len

      io.puts ""
      io.puts Logger.paint("Markdown Render Profile (top consumers)", Logger::Role::Heading, bold: true)

      io.puts "#{"Page".ljust(header_width)} | Count | #{" Bytes".rjust(10)} | #{"Time".rjust(10)}"
      io.puts "#{"-" * header_width}-+-------+#{"-" * 12}+#{"-" * 11}"

      # Show top 20 to avoid flooding output on large sites
      sorted.first(20).each do |mp|
        name = mp.path.ljust(header_width)
        count = mp.count.to_s.rjust(5)
        bytes = format_bytes(mp.total_bytes).rjust(10)
        time = format_time(mp.total_time_ms).rjust(10)
        io.puts "#{name} | #{count} | #{bytes} | #{time}"
      end

      if sorted.size > 20
        io.puts "  ... and #{sorted.size - 20} more pages (#{sorted.size} total)"
      end

      total_time = sorted.sum(&.total_time_ms)
      total_bytes = sorted.sum(&.total_bytes)
      io.puts "#{" " * header_width}   #{" " * 5}   #{" " * 10}  #{"─" * 10}"
      io.puts "#{" " * header_width}    Total#{" " * (10 + 5)} #{format_time(total_time).rjust(10)} (#{format_bytes(total_bytes)} processed)"
      io.puts ""
    end

    # Print timing for heavy BeforeRender asset generation (OG images + image resizing).
    # These often dominate the Render phase on sites with auto OG or responsive images enabled.
    def asset_report(io : IO = STDOUT)
      return unless @enabled
      return if @asset_stats.empty?

      io.puts ""
      io.puts Logger.paint("Asset Generation (OG + Image Hooks)", Logger::Role::Heading, bold: true)
      io.puts Logger.paint("─" * 60, Logger::Role::Dim)

      total_time = 0.0
      @asset_stats.each do |s|
        total_time += s.time_ms
        label = s.name.ljust(28)
        gen = "gen=#{s.generated}".rjust(10)
        skp = s.skipped > 0 ? " skip=#{s.skipped}" : ""
        t = format_time(s.time_ms).rjust(10)
        io.puts "  #{label} #{gen}#{skp}  #{t}"
      end

      io.puts Logger.paint("─" * 60, Logger::Role::Dim)
      io.puts "  Total asset generation time: #{format_time(total_time).rjust(10)}"
      io.puts ""
    end

    # Print timing for all lifecycle hooks that ran during the build.
    # This gives visibility into taxonomy, SEO, PWA, AMP, asset, and custom hooks.
    def hook_report(io : IO = STDOUT)
      return unless @enabled
      return if @hook_profiles.empty?

      sorted = @hook_profiles.values.sort_by! { |h| -h.total_time_ms }

      io.puts ""
      io.puts Logger.paint("Hook Profile", Logger::Role::Heading, bold: true)
      io.puts Logger.paint("─" * 60, Logger::Role::Dim)

      max_name_len = sorted.max_of(&.name.size)

      sorted.each do |h|
        name = h.name.ljust(max_name_len)
        count = "×#{h.count}".rjust(6)
        time = format_time(h.total_time_ms).rjust(10)
        io.puts "  #{name} #{count}  #{time}"
      end

      total_time = sorted.sum(&.total_time_ms)
      io.puts Logger.paint("─" * 60, Logger::Role::Dim)
      io.puts "  Total hook execution time: #{format_time(total_time).rjust(10)}"
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

    # Render a simple bar chart. Keeps the █/░ glyphs in every mode (the
    # profile layout is spec-pinned); only the paint follows the ember roles.
    private def render_bar(percent : Float64, width : Int32) : String
      filled = (percent / 100.0 * width).to_i
      filled = [filled, width].min
      fill = Logger.paint("█" * filled, Logger::Role::Accent)
      track = Logger.paint("░" * (width - filled), Logger::Role::Dim)
      "#{fill}#{track}"
    end
  end
end
