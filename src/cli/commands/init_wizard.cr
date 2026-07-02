require "../prompt"
require "../../config/options/init_options"
require "../../services/scaffolds/registry"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      # Guided, line-based wizard for `hwaro init` when invoked bare (no
      # option flags) in an interactive session. Mirrors `NewWizard`: it asks
      # one styled question at a time, shows a `Receipt` summary, and confirms
      # before anything touches the filesystem. It only *collects* input — the
      # resulting `InitOptions` flows through the exact same
      # `Services::Initializer` pipeline the flag form uses, so there is one
      # creation path, not two.
      class InitWizard
        # Base (light) scaffolds in presentation order. Dark variants are
        # reached through the "Dark theme?" toggle instead of tripling the
        # picker list.
        BASE_ORDER = [
          Config::Options::ScaffoldType::Simple,
          Config::Options::ScaffoldType::Blog,
          Config::Options::ScaffoldType::Docs,
          Config::Options::ScaffoldType::Book,
          Config::Options::ScaffoldType::Bare,
        ]

        DARK_VARIANTS = {
          Config::Options::ScaffoldType::Blog => Config::Options::ScaffoldType::BlogDark,
          Config::Options::ScaffoldType::Docs => Config::Options::ScaffoldType::DocsDark,
          Config::Options::ScaffoldType::Book => Config::Options::ScaffoldType::BookDark,
        }

        # Returns the collected `InitOptions`, or `nil` on cancellation — a
        # declined confirmation or an EOF (Ctrl-D) on any prompt — so the
        # caller can bail out without creating anything. A `path` positional
        # (e.g. `hwaro init my-site`) skips the directory prompt and uses that
        # path directly; a bare `hwaro init` still asks.
        def run(seed_path : String? = nil) : Config::Options::InitOptions?
          path = if seed = seed_path
                   Logger.heading("init", seed == "." ? nil : seed)
                   seed
                 else
                   Logger.heading("init")
                   asked = Prompt.ask("Directory", default: ".")
                   return if asked.nil?
                   asked
                 end

          labels = BASE_ORDER.map do |type|
            "#{type} — #{Services::Scaffolds::Registry.get(type).description}"
          end
          picked = Prompt.select("Scaffold", labels, skip_hint: "Enter for simple")
          scaffold = if picked && (idx = labels.index(picked))
                       BASE_ORDER[idx]
                     else
                       Config::Options::ScaffoldType::Simple
                     end

          title = Prompt.ask("Site title", default: "My Hwaro Site")
          return if title.nil?

          if dark_variant = DARK_VARIANTS[scaffold]?
            dark = Prompt.confirm?("Dark theme?", default: false)
            return if dark.nil?
            scaffold = dark_variant if dark
          end

          Logger::Receipt.new("init")
            .row("path", path == "." ? "current directory" : path)
            .row("scaffold", scaffold.to_s)
            .row("title", title)
            .emit

          return unless Prompt.confirm?("Create project?", default: true)

          Config::Options::InitOptions.new(
            path: path,
            scaffold: scaffold,
            site_title: title,
            from_wizard: true,
          )
        end
      end
    end
  end
end
