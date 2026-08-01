require "../prompt"
require "../../config/options/init_options"
require "../../services/scaffolds/registry"
require "../../utils/logger"

module Hwaro
  module CLI
    module Commands
      # Guided, line-based wizard for `hwaro init --wizard` in an interactive
      # session. Mirrors `NewWizard`: it asks
      # one styled question at a time, shows a `Receipt` summary, and confirms
      # before anything touches the filesystem. It only *collects* input — the
      # resulting `InitOptions` flows through the exact same
      # `Services::Initializer` pipeline the flag form uses, so there is one
      # creation path, not two.
      class InitWizard
        # Scaffolds in presentation order. Every scaffold follows the OS
        # color scheme automatically and ships a manual theme switcher, so
        # there is no separate dark-variant picker step.
        BASE_ORDER = [
          Config::Options::ScaffoldType::Simple,
          Config::Options::ScaffoldType::Blog,
          Config::Options::ScaffoldType::Docs,
          Config::Options::ScaffoldType::Book,
          Config::Options::ScaffoldType::Bare,
        ]

        # Returns the collected `InitOptions`, or `nil` on cancellation — a
        # declined confirmation or an EOF (Ctrl-D) on any prompt — so the
        # caller can bail out without creating anything.
        #
        # The wizard only asks for what the user has not already supplied on
        # the command line: a `path` positional (e.g. `hwaro init my-site
        # --wizard`) skips the directory prompt, and `--scaffold blog` skips
        # the scaffold picker. Every remaining flag rides in on `base` — which
        # is the fully parsed `InitOptions` — so `--force`, `--clean`,
        # `--skip-*`, `--minimal-config`/`--full-config`, `--agents` and
        # `--include-multilingual` keep working alongside `--wizard` instead
        # of being silently dropped.
        def run(
          seed_path : String? = nil,
          base : Config::Options::InitOptions? = nil,
          seed_scaffold : Config::Options::ScaffoldType? = nil,
        ) : Config::Options::InitOptions?
          # `InitOptions` is a struct, so this is a copy — mutating it here
          # cannot leak back into the caller's parsed options.
          options = base || Config::Options::InitOptions.new

          path = if seed = seed_path
                   Logger.heading("init", seed == "." ? nil : seed)
                   seed
                 else
                   Logger.heading("init")
                   asked = Prompt.ask("Directory", default: ".")
                   return if asked.nil?
                   asked
                 end

          # A remote scaffold (`--scaffold github:owner/repo`) has no entry in
          # the built-in picker, so it also skips the prompt.
          remote = options.scaffold_remote
          scaffold = if seed_scaffold || remote
                       seed_scaffold || options.scaffold
                     else
                       labels = BASE_ORDER.map do |type|
                         "#{type} — #{Services::Scaffolds::Registry.get(type).description}"
                       end
                       picked = Prompt.select("Scaffold", labels, skip_hint: "Enter for simple")
                       if picked && (idx = labels.index(picked))
                         BASE_ORDER[idx]
                       else
                         Config::Options::ScaffoldType::Simple
                       end
                     end

          title = Prompt.ask("Site title", default: "My Hwaro Site")
          return if title.nil?

          Logger::Receipt.new("init")
            .row("path", path == "." ? "current directory" : path)
            .row("scaffold", remote || scaffold.to_s)
            .row("title", title)
            .emit

          return unless Prompt.confirm?("Create project?", default: true)

          options.path = path
          options.scaffold = scaffold
          options.site_title = title
          options.from_wizard = true
          options
        end
      end
    end
  end
end
