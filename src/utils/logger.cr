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

    # Semantic color roles for the unified "ember" terminal identity.
    # Each role resolves to a truecolor RGB (when COLORTERM advertises it),
    # a 16-color named fallback, or raw text when color is disabled. This is
    # the single source of truth for brand color — callers name a role, never
    # a raw colorize symbol, so the palette stays consistent across commands.
    enum Role : UInt8
      Accent  # warm ember (#ec7a66 dark / #b35454 light) — headings, outcomes, URLs
      Success # green — a check passed
      Warn    # yellow
      Error   # red
      Dim     # recessive gray — labels, timings, paths, rules
      Heading # ember (alias of Accent, kept distinct for intent)
      Plain   # no color (default foreground)
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
      clear_active_line
      @@io.puts colorize("[DEBUG] #{message}", :light_gray)
    end

    def self.info(message : String)
      return if @@level > Level::Info
      return if @@quiet
      clear_active_line
      @@io.puts message
    end

    def self.error(message : String)
      clear_active_line
      @@err_io.puts colorize(message, :red)
    end

    def self.warn(message : String)
      return if @@level > Level::Warn
      clear_active_line
      @@err_io.puts colorize("[WARN] #{message}", :yellow)
    end

    def self.success(message : String)
      return if @@quiet
      clear_active_line
      @@io.puts colorize(message, :green)
    end

    def self.action(label : String | Symbol, message : String, color : Symbol = :green)
      return if @@quiet
      clear_active_line
      label_s = label.to_s.rjust(12)
      if color_enabled?
        @@io.puts "#{label_s.colorize(color).bold}  #{message}"
      else
        @@io.puts "#{label_s}  #{message}"
      end
    end

    # Performance timing helper
    def self.timed(message : String, &)
      start = Time.instant
      result = yield
      elapsed = Time.instant - start
      info "#{message} (#{dur(elapsed.total_milliseconds)})"
      result
    end

    # Progress indicator for long operations.
    # In TTY mode: animated \r-overwriting bar.
    # In non-TTY mode (pipes, CI, agent capture, redirected files):
    # suppress the per-step animation — `\r` doesn't return to column 0
    # there, so every step concatenates into one giant smeared line. Emit
    # only a final "<prefix>done (current/total)" line so logs stay readable.
    def self.progress(current : Int32, total : Int32, prefix : String = "")
      return if total <= 0
      return if @@quiet
      unless @@io.tty?
        @@io.puts "#{prefix}done (#{current}/#{total})" if current >= total
        return
      end
      percent = (current.to_f / total * 100).round(1)
      bar_width = 30
      filled = (current.to_f / total * bar_width).to_i
      bar = "█" * filled + "░" * (bar_width - filled)
      @@io.print "\r#{prefix}[#{bar}] #{percent}% (#{current}/#{total})"
      @@io.puts if current >= total
    end

    # ---------------------------------------------------------------------
    # Ember theme: roles, glyphs, and humanized durations
    # ---------------------------------------------------------------------

    # True only when the terminal advertises 24-bit color *and* color is
    # otherwise enabled. Gates the truecolor tier; everything degrades to the
    # 16-color named fallback below it, then to raw text.
    def self.truecolor? : Bool
      return false unless color_enabled?
      v = ENV["COLORTERM"]?
      v == "truecolor" || v == "24bit"
    end

    # Background brightness for the ember accent. Not auto-detected (terminals
    # don't report it reliably); default to the dark-bg ember and let users
    # override with `HWARO_THEME=light`.
    def self.dark? : Bool
      ENV["HWARO_THEME"]? != "light"
    end

    # Truecolor RGB for a role, honoring `dark?`. `nil` for Plain.
    private def self.role_rgb(role : Role) : Tuple(UInt8, UInt8, UInt8)?
      dark = dark?
      case role
      when .accent?, .heading? then dark ? {236_u8, 122_u8, 102_u8} : {179_u8, 84_u8, 84_u8}
      when .success?           then dark ? {184_u8, 187_u8, 38_u8} : {90_u8, 130_u8, 80_u8}
      when .warn?              then dark ? {250_u8, 189_u8, 47_u8} : {181_u8, 118_u8, 58_u8}
      when .error?             then dark ? {251_u8, 73_u8, 52_u8} : {192_u8, 57_u8, 43_u8}
      when .dim?               then dark ? {146_u8, 131_u8, 116_u8} : {138_u8, 128_u8, 118_u8}
      end
    end

    # 16-color named fallback for a role. `nil` for Plain.
    private def self.role_named(role : Role) : Symbol?
      case role
      when .accent?, .heading? then :light_red # distinct from Error's :red
      when .success?           then :green
      when .warn?              then :yellow
      when .error?             then :red
      when .dim?               then :light_gray
      end
    end

    # Paint `text` in a semantic role. Returns raw text (no escapes) when
    # color is disabled, so scripts / CI / pipes stay clean. Prefers truecolor,
    # falls back to the 16-color name, then to plain.
    def self.paint(text : String, role : Role, bold : Bool = false) : String
      unless color_enabled?
        return text
      end
      colored =
        if (rgb = role_rgb(role)) && truecolor?
          text.colorize(Colorize::ColorRGB.new(rgb[0], rgb[1], rgb[2]))
        elsif named = role_named(role)
          text.colorize(named)
        else
          text.colorize
        end
      (bold ? colored.bold : colored).to_s
    end

    # Glyph registry: {unicode, ascii-fallback, role}. The ASCII fallback is
    # used whenever color/unicode is disabled — the same gate the rest of the
    # CLI uses — so plain output never emits a stray multibyte glyph.
    GLYPHS = {
      :ok      => {"✓", "[ok]", Role::Success},
      :warn    => {"⚠", "[warn]", Role::Warn},
      :err     => {"✗", "[err]", Role::Error},
      :info    => {"ℹ", "[info]", Role::Dim},
      :result  => {"▴", "*", Role::Accent},
      :heading => {"●", "#", Role::Accent},
      :ready   => {"◇", ">", Role::Accent},
      :watch   => {"↻", "~", Role::Accent},
    }

    # Resolve a glyph by key: colorized unicode when color is on, else the
    # plain ASCII fallback.
    def self.glyph(key : Symbol) : String
      uni, ascii, role = GLYPHS[key]
      color_enabled? ? paint(uni, role) : ascii
    end

    # Humanized duration: ">= 1s" renders as seconds with two decimals
    # ("1.18s"), below a second as whole milliseconds ("842ms"). Replaces the
    # scattered `.round(2)}ms` so timings read consistently everywhere.
    def self.dur(ms : Float64) : String
      return "#{"%.2f" % (ms / 1000.0)}s" if ms >= 1000.0
      "#{ms.round.to_i}ms"
    end

    # Total visible width of a receipt heading / divider rule.
    RECEIPT_WIDTH = 48

    # TTY form of a command heading: "  ● kind  title ───────". The glyph and
    # rule are dim/ember; the trailing rule fills to RECEIPT_WIDTH. Used by
    # `heading` and by `Receipt`.
    def self.heading_str(kind : String, title : String? = nil) : String
      head = "#{glyph(:heading)} #{paint(kind, Role::Dim, bold: true)}"
      visible = 4 + kind.size # 2 indent + glyph + space + kind
      if t = title
        head = "#{head} #{paint(t, Role::Plain, bold: true)}"
        visible += 1 + t.size
      end
      fill = RECEIPT_WIDTH - visible - 1
      fill > 0 ? "  #{head} #{paint("─" * fill, Role::Dim)}" : "  #{head}"
    end

    # Print a command heading. No-ops in quiet; degrades to "hwaro: kind title"
    # when color is off (no glyph, no rule).
    def self.heading(kind : String, title : String? = nil) : Nil
      return if @@quiet
      clear_active_line
      if color_enabled?
        @@io.puts heading_str(kind, title)
      else
        @@io.puts(title ? "hwaro: #{kind} #{title}" : "hwaro: #{kind}")
      end
    end

    # Build the single outcome line. `col` left-pads the verb so it aligns with
    # a receipt's row labels. Plain form is "verb: value[ in dur]" with the
    # middot separators flattened to commas.
    def self.outcome_str(verb : String, value : String, glyph : Symbol, ms : Float64?, col : Int32, plain : Bool) : String
      if plain
        line = "#{verb}: #{value.gsub(" · ", ", ")}"
        line += " in #{dur(ms)}" if ms
        line
      else
        line = "  #{self.glyph(glyph)} #{paint(verb.ljust(col), Role::Accent, bold: true)}  #{value}"
        line += "#{paint("  ·  ", Role::Dim)}#{paint(dur(ms), Role::Dim)}" if ms
        line
      end
    end

    # Print a standalone outcome line — the one warm ember beat a command ends
    # on (`▴ created  path`). The glyph signals severity (`:result` ember,
    # `:warn`/`:err` for problems) while the verb is always ember.
    def self.outcome(verb : String, value : String, glyph : Symbol = :result, ms : Float64? = nil, col : Int32 = 0) : Nil
      return if @@quiet
      clear_active_line
      @@io.puts outcome_str(verb, value, glyph, ms, col, !color_enabled?)
    end

    # A calm, aligned summary block: a heading, key/value rows, a divider, and
    # one ember outcome line. Pure data → string, so it renders identically and
    # testably without a live terminal. `render_tty` is emitted only when color
    # is on; `render_plain` is the escape-free fallback for pipes / CI.
    class Receipt
      private record Row,
        label : String,
        value : String,
        role : Role,
        emphasis : String?,
        emphasis_role : Role

      @rows : Array(Row)
      @outcome : NamedTuple(verb: String, value: String, glyph: Symbol, ms: Float64?)?

      def initialize(@kind : String, @title : String? = nil)
        @rows = [] of Row
        @outcome = nil
      end

      # Append a key/value row. Skipped when empty so the summary never prints
      # noise like "0 drafts". `emphasis` is an optional differently-colored
      # suffix (e.g. a yellow "2 drafts skipped").
      def row(label : String, value : String, role : Role = Role::Plain, emphasis : String? = nil, emphasis_role : Role = Role::Warn) : self
        @rows << Row.new(label, value, role, emphasis, emphasis_role) unless value.empty? && emphasis.nil?
        self
      end

      def outcome(verb : String, value : String, glyph : Symbol = :result, ms : Float64? = nil) : self
        @outcome = {verb: verb, value: value, glyph: glyph, ms: ms}
        self
      end

      # Print using the renderer that matches the current terminal.
      def emit(io : IO = Logger.io) : Nil
        return if Logger.quiet?
        io.puts(Logger.color_enabled? ? render_tty : render_plain)
      end

      # Label column width: the longest row label, also covering the outcome
      # verb so row values and the outcome value share one column.
      private def col : Int32
        w = @rows.max_of?(&.label.size) || 0
        if o = @outcome
          w = {w, o[:verb].size}.max
        end
        w
      end

      def render_tty : String
        width = col
        lines = [Logger.heading_str(@kind, @title)]
        @rows.each do |r|
          cell = Logger.paint(r.value, r.role)
          if e = r.emphasis
            cell = "#{cell}#{Logger.paint(" · ", Role::Dim)}#{Logger.paint(e, r.emphasis_role)}"
          end
          lines << "    #{Logger.paint(r.label.ljust(width), Role::Dim)}  #{cell}"
        end
        if o = @outcome
          lines << "  #{Logger.paint("─" * (RECEIPT_WIDTH - 2), Role::Dim)}"
          lines << Logger.outcome_str(o[:verb], o[:value], o[:glyph], o[:ms], width, false)
        end
        lines.join("\n")
      end

      def render_plain : String
        lines = [@title ? "hwaro: #{@kind} #{@title}" : "hwaro: #{@kind}"]
        @rows.each do |r|
          val = r.value.gsub(" · ", ", ")
          val = "#{val}, #{r.emphasis}" if r.emphasis
          lines << "#{r.label}: #{val}"
        end
        if o = @outcome
          lines << Logger.outcome_str(o[:verb], o[:value], o[:glyph], o[:ms], 0, true)
        end
        lines.join("\n")
      end
    end

    # ---------------------------------------------------------------------
    # Live status region (TTY only)
    # ---------------------------------------------------------------------
    #
    # A single \r-overwriting line that breathes the current phase while work
    # runs, then erases itself so the calm receipt is all that remains in
    # scrollback. It is the ONLY place that emits `\r` / cursor escapes, and it
    # never activates unless STDOUT is a TTY with color and non-quiet output —
    # so pipes, CI, NO_COLOR, and tests are completely untouched (no fiber, no
    # escapes). Animation is driven by a timer fiber, decoupled from the build's
    # (possibly parallel) work so motion stays smooth regardless of phase.
    class Status
      SPINNER  = %w[◐ ◓ ◑ ◒]
      INTERVAL = 90.milliseconds

      def initialize(@io : IO)
        @label = ""
        @start = Time.instant
        @frame = 0
        @stopped = Atomic(Int32).new(0)
        # Buffered (capacity 1) so the timer fiber's final send never blocks,
        # even if `stop` is never reached — no parked/leaked fiber.
        @done = Channel(Nil).new(1)
        @active = false
        # Serializes terminal writes and shared-state (@label/@frame) access
        # between the timer fiber and the main fiber under -Dpreview_mt.
        @mutex = Mutex.new
      end

      def start : Nil
        @active = true
        spawn do
          until @stopped.get == 1
            draw
            sleep INTERVAL
          end
        ensure
          # Always erase our line and signal `stop`, even if `draw` raised
          # (e.g. the TTY went away mid-build). Without this, `stop`'s
          # `@done.receive` — reached from the build's `ensure` — would
          # deadlock the whole process.
          erase
          @done.send(nil)
        end
      end

      # Update the label and redraw immediately. The synchronous redraw is what
      # makes phase progression visible even when CPU-bound work starves the
      # timer fiber (Crystal's scheduler only services the sleep timer at yield
      # points); the timer still adds animation whenever the build yields.
      def phase(label : String) : Nil
        return unless @active
        @mutex.synchronize { @label = label }
        draw
      end

      # Stop the timer fiber and wait for it to erase its line, so subsequent
      # output (the receipt) prints on a clean line. Idempotent.
      def stop : Nil
        return unless @active
        @active = false
        @stopped.set(1)
        @done.receive
      end

      # Erase the spinner's current line without stopping it — used by the
      # logging methods so an interleaved warning/info prints cleanly and the
      # spinner simply redraws below it on its next tick.
      def clear_line : Nil
        return unless @active
        erase
      end

      private def erase : Nil
        write "\r\e[K"
      end

      private def draw : Nil
        line = @mutex.synchronize do
          frame = SPINNER[@frame % SPINNER.size]
          @frame += 1
          elapsed = Logger.dur((Time.instant - @start).total_milliseconds)
          body = @label.empty? ? "working" : @label
          "\r\e[K#{Logger.paint(frame, Role::Accent)} " \
          "#{Logger.paint(body, Role::Dim)} " \
          "#{Logger.paint("· #{elapsed}", Role::Dim)}"
        end
        write line
      end

      # Single guarded terminal writer. If the TTY disappears mid-build
      # (SIGHUP / EPIPE / EIO), stop the spinner instead of raising into the
      # build or spinning uselessly — the receipt still prints afterwards.
      private def write(s : String) : Nil
        @mutex.synchronize do
          @io.print s
          @io.flush
        end
      rescue IO::Error
        @stopped.set(1)
      end
    end

    @@active_status : Status? = nil

    # Begin a live status region for a unit of work. No-ops (and spawns no
    # fiber) unless output is an interactive, colored, non-quiet TTY. `verbose`
    # disables it too, since verbose mode streams its own per-file lines that
    # would fight the spinner.
    def self.status_start(verbose : Bool = false) : Nil
      return if @@active_status # never nest
      return if verbose || @@quiet
      return unless @@io.tty? && color_enabled?
      status = Status.new(@@io)
      @@active_status = status
      status.start
    end

    # Update the active status label (e.g. "render"). No-op when inactive.
    def self.status_phase(label : String) : Nil
      @@active_status.try(&.phase(label))
    end

    # Stop and tear down the active status region. Idempotent.
    def self.status_finish : Nil
      if status = @@active_status
        @@active_status = nil
        status.stop
      end
    end

    # Erase the active spinner line before other output prints. Called by the
    # logging methods so the live region coexists with normal log lines.
    private def self.clear_active_line : Nil
      @@active_status.try(&.clear_line)
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
