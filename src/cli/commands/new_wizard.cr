require "../prompt"
require "../../config/options/new_options"
require "../../services/creator"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      # Guided, line-based wizard for `hwaro new` when no `<path>` was given and
      # the session is interactive. It asks one question at a time (styled with
      # the shared ember identity), shows a `Receipt` summary, then confirms
      # before any file is written. It only *collects* input — the resulting
      # `NewOptions` flows back through the exact same validate/sanitize/create
      # pipeline the flag form uses, so there is one creation path, not two.
      class NewWizard
        CONTENT_DIR = "content"

        alias Archetype = NamedTuple(name: String, path: String)

        # Mutates `options` in place and returns `true` to proceed with creation.
        # Returns `false` on cancellation — a declined confirmation or an EOF
        # (Ctrl-D) on a required answer — so the caller can bail out cleanly
        # without creating anything.
        #
        # Any flags already supplied (`--title`, `--tags`, …) seed the matching
        # prompt's default, so `hwaro new --title "Foo"` asks only for the rest.
        def run(options : Config::Options::NewOptions, archetypes : Array(Archetype) = [] of Archetype) : Bool
          Logger.heading("new")

          # --- Title (required) — drives the recommended path slug.
          title = if (seed = options.title) && !seed.empty?
                    Prompt.ask("Title", default: seed)
                  else
                    Prompt.ask_required("Title")
                  end
          return false if title.nil?

          # --- Description (optional).
          description = Prompt.ask("Description", default: options.description)

          # --- Section (optional) — only used to shape the recommended path.
          sections = detect_sections
          hint = sections.empty? ? "optional, e.g. posts, blog, docs" : "detected: #{sections.join(", ")}"
          section = Prompt.ask("Section (#{hint})", default: options.section)

          # --- Path (required) — default is the recommended <section>/<slug>.md.
          slug = Hwaro::Services::Creator.slugify(title)
          suggested = if slug.empty?
                        nil
                      elsif (s = section) && !s.empty?
                        "#{s}/#{slug}.md"
                      else
                        "#{slug}.md"
                      end
          path = suggested ? Prompt.ask("Path", default: suggested) : Prompt.ask_required("Path")
          return false if path.nil?

          display_path = path.starts_with?("#{CONTENT_DIR}/") ? path : File.join(CONTENT_DIR, path)
          if File.exists?(display_path)
            Logger.warn "  #{display_path} already exists — creation will be rejected unless you pick another path."
          end

          # --- Tags (optional) — comma-separated, same parsing as the flag.
          tags_default = options.tags.empty? ? nil : options.tags.join(", ")
          tags_input = Prompt.ask("Tags (comma-separated)", default: tags_default)
          tags = tags_input ? tags_input.split(",").map(&.strip).reject(&.empty?) : [] of String

          # --- Date (optional) — defaults to today; only pinned if changed.
          today = Time.local.to_s("%Y-%m-%d")
          date_value = Prompt.ask("Date", default: options.date || today)
          return false if date_value.nil?

          # --- Draft toggle.
          draft = Prompt.confirm?("Mark as draft?", default: options.draft == true)
          return false if draft.nil?

          # --- Archetype (only when the project ships any).
          archetype = options.archetype
          unless archetypes.empty?
            picked = Prompt.select("Archetype", archetypes.map(&.[:name]))
            archetype = picked unless picked.nil?
          end

          # --- Summary + confirmation.
          Logger::Receipt.new("new")
            .row("path", display_path)
            .row("title", title)
            .row("description", description || "")
            .row("tags", tags.join(", "))
            .row("date", date_value)
            .row("draft", draft ? "yes" : "no")
            .row("archetype", archetype || "")
            .emit

          return false unless Prompt.confirm?("Create #{display_path}?", default: true)

          options.title = title
          options.description = description
          options.path = path
          options.tags = tags
          # Leave `date` unset when the author accepted today's default so the
          # Creator stamps it at write time; pin it only when they changed it.
          options.date = (date_value == today ? nil : date_value)
          options.draft = draft
          options.archetype = archetype
          # The section was a path-building aid only; we baked it into `path`.
          # Clearing it keeps `path` the single source of truth and avoids the
          # Creator's resolve_section double-join.
          options.section = nil
          true
        end

        # Immediate subdirectories of content/, sorted, used purely as a hint so
        # the author knows which sections already exist. Missing content/ (or any
        # IO hiccup) simply yields no hint rather than failing the wizard.
        private def detect_sections : Array(String)
          return [] of String unless Dir.exists?(CONTENT_DIR)
          Dir.children(CONTENT_DIR).select { |c| Dir.exists?(File.join(CONTENT_DIR, c)) }.sort!
        rescue
          [] of String
        end
      end
    end
  end
end
