# Initializer module for creating new Hwaro projects
#
# Creates the initial project structure with sample content,
# templates, and configuration based on the selected scaffold.

require "file_utils"
require "../config/options/init_options"
require "../utils/errors"
require "../utils/file_safe"
require "../utils/logger"
require "../services/scaffolds/registry"
require "../services/scaffolds/remote"
require "./defaults/agents_md"
require "./doctor"
require "./config_snippets"

module Hwaro
  module Services
    class Initializer
      # One scaffold write, remembered instead of streamed: TTY output renders
      # the collected entries as a grouped tree at the end (24 near-identical
      # "create" lines collapse into one line per top-level entry), while
      # plain/piped output replays them as the historical per-file
      # "      create  path" lines, byte-for-byte.
      private record ScaffoldEntry, action : Symbol, path : String, dir : Bool

      # Counts files/directories actually created so the closing receipt can
      # report "N files" (existing entries left in place are not counted).
      @created_count = 0

      @entries = [] of ScaffoldEntry

      def run(options : Config::Options::InitOptions)
        scaffold = if remote = options.scaffold_remote
                     Scaffolds::Remote.new(remote)
                   else
                     Scaffolds::Registry.get(options.scaffold)
                   end

        run_with_scaffold(
          options.path,
          options.force,
          options.skip_agents_md,
          options.skip_sample_content,
          options.skip_taxonomies,
          options.multilingual_languages,
          scaffold,
          options.agents_mode,
          options.minimal_config,
          options.full_config,
          options.clean,
          options.site_title,
          options.from_wizard
        )
      end

      def run(
        target_path : String,
        force : Bool = false,
        skip_agents_md : Bool = false,
        skip_sample_content : Bool = false,
        skip_taxonomies : Bool = false,
        multilingual_languages : Array(String) = [] of String,
        scaffold_type : Config::Options::ScaffoldType = Config::Options::ScaffoldType::Simple,
        agents_mode : Config::Options::AgentsMode = Config::Options::AgentsMode::Remote,
        minimal_config : Bool = false,
        full_config : Bool = false,
        clean : Bool = false,
      )
        scaffold = Scaffolds::Registry.get(scaffold_type)
        run_with_scaffold(target_path, force, skip_agents_md, skip_sample_content, skip_taxonomies, multilingual_languages, scaffold, agents_mode, minimal_config, full_config, clean)
      end

      private def run_with_scaffold(
        target_path : String,
        force : Bool,
        skip_agents_md : Bool,
        skip_sample_content : Bool,
        skip_taxonomies : Bool,
        multilingual_languages : Array(String),
        scaffold : Scaffolds::Base,
        agents_mode : Config::Options::AgentsMode = Config::Options::AgentsMode::Remote,
        minimal_config : Bool = false,
        full_config : Bool = false,
        clean : Bool = false,
        site_title : String? = nil,
        from_wizard : Bool = false,
      )
        if clean && Dir.exists?(target_path) && !Dir.empty?(target_path)
          clean_target(target_path)
        end

        unless Dir.exists?(target_path)
          Hwaro::Utils::FileSafe.mkdir_p(target_path)
        end

        # --clean wipes the dir up front; --force allows non-empty target but
        # keeps any existing files in place (only adds missing scaffold files).
        # Neither blindly overwrites user content.
        unless force || clean || Dir.empty?(target_path)
          Logger.error "Directory '#{target_path}' is not empty."
          Logger.error "Use --force to proceed (keeps existing files, adds missing scaffold files), or --clean to remove existing files first."
          exit(1)
        end

        # The wizard already rendered the heading and a scaffold/title receipt;
        # printing them again here would double the header beat. The TTY form
        # sits on the 4-space grid with the tree below it; the plain form
        # keeps its historical 2-space indent.
        unless from_wizard
          Logger.heading("init", target_path == "." ? nil : target_path)
          if Logger.color_enabled?
            Logger.info "    #{Logger.paint("scaffold", Logger::Role::Dim)}  #{Logger.paint(scaffold.description, Logger::Role::Dim)}"
          else
            Logger.info "  scaffold  #{scaffold.description}"
          end
        end

        is_multilingual = multilingual_languages.size > 1

        if multilingual_languages.size == 1
          Logger.warn "  --include-multilingual needs 2+ languages; '#{multilingual_languages.first}' alone is treated as non-multilingual."
        end

        if minimal_config && is_multilingual
          Logger.warn "  --minimal-config does not include multilingual settings; ignoring --include-multilingual"
        end

        # Create content structure
        create_directory(File.join(target_path, "content"))

        unless skip_sample_content
          if is_multilingual
            create_multilingual_content(target_path, multilingual_languages, skip_taxonomies, scaffold)
          else
            create_scaffold_content(target_path, scaffold, skip_taxonomies)
          end
        end

        # Create templates
        create_scaffold_templates(target_path, scaffold, skip_taxonomies)

        # Create static directory
        create_directory(File.join(target_path, "static"))

        # Create static files
        create_scaffold_static_files(target_path, scaffold)

        # Create archetype files so `hwaro new` has templates to match
        # against and the archetype convention is discoverable.
        create_scaffold_archetypes(target_path, scaffold)

        # Create config.toml
        # Hybrid philosophy (C):
        # - minimal_config : bare essentials, no comments
        # - full_config    : maximum discoverability (current verbose behavior + doctor injection)
        # - default        : balanced (core + commonly useful sections with light comments)
        if scaffold.is_a?(Scaffolds::Remote)
          remote_config = scaffold.config_content(skip_taxonomies, multilingual_languages)
          if remote_config.strip.empty?
            # Remote scaffold had no config.toml (allowed for content/templates-only remotes).
            # Fall back to normal generation logic so we don't write an empty config.toml.
            Logger.warn "Remote scaffold did not include a config.toml; generating a default one."
            if minimal_config
              config_content = scaffold.minimal_config_content(skip_taxonomies, multilingual_languages)
            elsif full_config
              # For --full-config without upstream config, use the balanced discoverable default
              # (we can't easily reconstruct a "full" from a non-remote scaffold here).
              config_content = build_balanced_default_config(scaffold, skip_taxonomies, is_multilingual, multilingual_languages)
            else
              config_content = build_balanced_default_config(scaffold, skip_taxonomies, is_multilingual, multilingual_languages)
            end
          else
            # Use the remote's config as-is (respecting its custom settings), ignore --min/--full.
            config_content = remote_config
          end
        elsif minimal_config
          config_content = scaffold.minimal_config_content(skip_taxonomies, multilingual_languages)
        elsif full_config
          config_content = scaffold.config_content(skip_taxonomies, multilingual_languages)
        else
          config_content = build_balanced_default_config(scaffold, skip_taxonomies, is_multilingual, multilingual_languages)
        end

        # Wizard-collected site title: substitute the first `title = "…"` line
        # of the generated config. Built-in scaffolds only — a remote
        # scaffold's config is used verbatim.
        if (title = site_title) && !title.empty? && !scaffold.is_a?(Scaffolds::Remote)
          escaped = title.gsub("\\", "\\\\").gsub("\"", "\\\"")
          config_content = config_content.sub(/^title\s*=\s*"[^"\n]*"/m, "title = \"#{escaped}\"")
        end

        create_file(File.join(target_path, "config.toml"), config_content)

        # Create AGENTS.md unless skipped
        unless skip_agents_md
          agents_content = case agents_mode
                           when Config::Options::AgentsMode::Local
                             Defaults::AgentsMd.content
                           when Config::Options::AgentsMode::Remote
                             Defaults::AgentsMd.remote_content
                           else
                             Defaults::AgentsMd.remote_content
                           end
          create_file(File.join(target_path, "AGENTS.md"), agents_content)
        end

        # Auto-add missing optional config sections (commented out).
        # Only for built-in scaffolds + full_config (remote provides its own config).
        if full_config && !scaffold.is_a?(Scaffolds::Remote)
          config_path = File.join(target_path, "config.toml")
          doctor = Services::Doctor.new(
            content_dir: File.join(target_path, "content"),
            config_path: config_path
          )
          summary = doctor.fix_config(approve_sections: true)
          unless summary.sections_added.empty?
            Logger.debug "Added #{summary.sections_added.size} optional config section(s) (commented out)."
          end
        end

        display_target = target_path == "." ? "." : "#{target_path}/"
        emit_scaffold_log(target_path)
        if Logger.color_enabled?
          # Close the frame like a Receipt: dim rule, ember outcome, then
          # hint rows whose labels align under the outcome verb.
          Logger.info "  #{Logger.paint("─" * (Logger::RECEIPT_WIDTH - 2), Logger::Role::Dim)}"
          Logger.outcome("created", "#{@created_count} files · #{display_target}")
          hint_col = "created".size
          Logger.info "    #{Logger.paint("next".ljust(hint_col), Logger::Role::Dim)}  hwaro build · hwaro serve to preview"
          Logger.info "    #{Logger.paint("deploy".ljust(hint_col), Logger::Role::Dim)}  set base_url in config.toml first (defaults to http://localhost:3000)"
        else
          Logger.outcome("created", "#{@created_count} files · #{display_target}")
          Logger.info "Run `hwaro build` to generate the site, then `hwaro serve` to preview."
          Logger.info "Set `base_url` in config.toml before deploying (defaults to http://localhost:3000)."
        end
      end

      # Emit the collected scaffold writes. Plain output replays the exact
      # per-file action lines the CLI has always printed (scripts and specs
      # match on them); a colored TTY gets the grouped tree instead.
      private def emit_scaffold_log(target_path : String)
        return if Logger.quiet?
        if Logger.color_enabled?
          emit_scaffold_tree(target_path)
        else
          @entries.each do |entry|
            role = entry.action == :exist ? Logger::Role::Dim : Logger::Role::Success
            Logger.action entry.action, entry.path, role
          end
        end
      end

      # Grouped tree summary of the scaffold: one row per top-level entry in
      # creation order, with a dim per-group note (file count, notable
      # subdirectories, kept-existing count). Dirs get a trailing slash.
      private def emit_scaffold_tree(target_path : String)
        group_order = [] of String
        group_dir = {} of String => Bool
        created = Hash(String, Int32).new(0)
        kept = Hash(String, Int32).new(0)
        subdirs = {} of String => Array(String)

        @entries.each do |entry|
          rel = Path[entry.path].relative_to(target_path).to_s
          next if rel == "." || rel.empty?
          parts = rel.split('/')
          top = parts.first
          unless group_dir.has_key?(top)
            group_order << top
            group_dir[top] = entry.dir || parts.size > 1
          end
          if parts.size == 1
            kept[top] += 1 if entry.action == :exist && !entry.dir
          elsif entry.dir
            (subdirs[top] ||= [] of String) << parts[1] if parts.size == 2
          else
            entry.action == :exist ? (kept[top] += 1) : (created[top] += 1)
          end
        end
        return if group_order.empty?

        width = group_order.max_of { |name| name.size + (group_dir[name] ? 1 : 0) }
        group_order.each_with_index do |name, i|
          connector = Logger.glyph(i == group_order.size - 1 ? :tree_last : :tree_mid)
          display = group_dir[name] ? "#{name}/" : name
          notes = [] of String
          if group_dir[name]
            n = created[name]
            notes << "#{n} #{n == 1 ? "file" : "files"}" if n > 0
            subdirs[name]?.try(&.uniq.each { |d| notes << "#{d}/" })
          end
          notes << "#{kept[name]} kept" if kept[name] > 0
          # Pad only when a note follows, so bare rows carry no trailing blanks.
          line = "    #{connector} "
          if notes.empty?
            line += display
          else
            line += "#{display.ljust(width)}  #{Logger.paint(notes.join(" · "), Logger::Role::Dim)}"
          end
          Logger.info line
        end
      end

      # Write each {relative_path => content} entry under base_dir, creating
      # parent directories on demand. Hash iteration order is preserved, so the
      # @created_count tally and the recorded entry sequence are unchanged.
      private def write_files(base_dir : String, files : Hash(String, String))
        files.each do |relative_path, content|
          full_path = File.join(base_dir, relative_path)
          dir_path = File.dirname(full_path)
          create_directory(dir_path) unless Dir.exists?(dir_path)
          create_file(full_path, content)
        end
      end

      private def create_scaffold_content(target_path : String, scaffold : Scaffolds::Base, skip_taxonomies : Bool)
        content_files = scaffold.content_files(skip_taxonomies)
        write_files(File.join(target_path, "content"), content_files)
      end

      private def create_scaffold_templates(target_path : String, scaffold : Scaffolds::Base, skip_taxonomies : Bool)
        templates_dir = File.join(target_path, "templates")
        create_directory(templates_dir)

        # Create template files. Some scaffolds emit nested paths
        # (e.g. `partials/nav.html`) so the parent directory is
        # created on demand instead of relying on a flat layout.
        template_files = scaffold.template_files(skip_taxonomies)
        write_files(templates_dir, template_files)

        # Create shortcodes directory and files only if the scaffold ships any.
        # (Bare scaffold returns empty to stay truly minimal.)
        shortcode_files = scaffold.shortcode_files
        unless shortcode_files.empty?
          shortcodes_dir = File.join(templates_dir, "shortcodes")
          create_directory(shortcodes_dir)

          shortcode_files.each do |relative_path, content|
            full_path = File.join(templates_dir, relative_path)
            create_file(full_path, content)
          end
        end
      end

      # Writes the scaffold's archetype files under `archetypes/` so
      # `hwaro new` can match them via `Services::Creator#find_archetype`.
      # Creating the directory — even for scaffolds that ship no archetype
      # files (e.g. remote) — would leave a confusing empty folder, so we
      # skip both directory creation and file writes when the scaffold
      # returns no archetypes.
      private def create_scaffold_archetypes(target_path : String, scaffold : Scaffolds::Base)
        archetype_files = scaffold.archetype_files
        return if archetype_files.empty?

        archetypes_dir = File.join(target_path, "archetypes")
        create_directory(archetypes_dir)

        write_files(archetypes_dir, archetype_files)
      end

      private def create_scaffold_static_files(target_path : String, scaffold : Scaffolds::Base)
        static_dir = File.join(target_path, "static")
        write_files(static_dir, scaffold.static_files)
      end

      private def create_multilingual_content(
        target_path : String,
        languages : Array(String),
        skip_taxonomies : Bool,
        scaffold : Scaffolds::Base,
      )
        content_dir = File.join(target_path, "content")
        write_files(content_dir, scaffold.multilingual_content_files(languages, skip_taxonomies))
      end

      private def language_display_name(code : String) : String
        case code.downcase
        when "en" then "English"
        when "ko" then "한국어"
        when "ja" then "日本語"
        when "zh" then "中文"
        when "es" then "Español"
        when "fr" then "Français"
        when "de" then "Deutsch"
        when "pt" then "Português"
        when "ru" then "Русский"
        when "it" then "Italiano"
        when "nl" then "Nederlands"
        when "pl" then "Polski"
        when "vi" then "Tiếng Việt"
        when "th" then "ไทย"
        when "ar" then "العربية"
        when "hi" then "हिन्दी"
        else           code.upcase
        end
      end

      # Remove every entry inside `target_path`, keeping the directory
      # itself. Refuses to touch a target that contains `.git/` so a
      # typo'd path or an accidental `--clean .` in a real repo can't
      # wipe the user's work.
      private def clean_target(target_path : String)
        if Dir.exists?(File.join(target_path, ".git"))
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "Refusing to --clean '#{target_path}': target contains a .git directory.",
            hint: "Delete .git manually if you really want to wipe this directory.",
          )
        end

        entries = Dir.children(target_path)
        return if entries.empty?

        Logger.info "Cleaning #{entries.size} existing entr#{entries.size == 1 ? "y" : "ies"} from '#{target_path}'..."
        entries.each do |entry|
          full = File.join(target_path, entry)
          FileUtils.rm_rf(full)
          Logger.action :remove, full, Logger::Role::Warn
        end
      end

      private def create_directory(path : String)
        if Dir.exists?(path)
          @entries << ScaffoldEntry.new(:exist, path, dir: true)
        else
          Hwaro::Utils::FileSafe.mkdir_p(path)
          @created_count += 1
          @entries << ScaffoldEntry.new(:create, path, dir: true)
        end
      end

      private def create_file(path : String, content : String)
        if File.exists?(path)
          @entries << ScaffoldEntry.new(:exist, path, dir: false)
        else
          File.write(path, content)
          @created_count += 1
          @entries << ScaffoldEntry.new(:create, path, dir: false)
        end
      end

      # Builds a balanced default config for Hybrid C.
      # Starts from the minimal base and adds the most commonly useful sections
      # with relatively light comments (not the full verbose monster).
      private def build_balanced_default_config(
        scaffold : Scaffolds::Base,
        skip_taxonomies : Bool,
        is_multilingual : Bool,
        multilingual_languages : Array(String),
      ) : String
        # Start with the clean minimal content (which now includes multilingual
        # block when languages.size > 1, plus sitemap/feeds/search etc.)
        base = scaffold.minimal_config_content(skip_taxonomies, multilingual_languages)

        str = String.build do |io|
          io << base

          # Add a few high-value sections with light comments (not full examples).
          # Note: sitemap/feeds are already provided by minimal_config_content
          # (avoiding the previous duplicate-key TOML errors).
          io << "\n# =============================================================================\n"
          io << "# OpenGraph & Twitter Cards (recommended for social sharing)\n"
          io << "# =============================================================================\n\n"
          io << "[og]\n"
          io << "type = \"article\"\n"
          io << "twitter_card = \"summary_large_image\"\n\n"

          io << "# =============================================================================\n"
          io << "# Markdown (commonly customized)\n"
          io << "# =============================================================================\n\n"
          io << "[markdown]\n"
          io << "emoji = true\n"
          io << "task_lists = true\n"
          io << "definition_lists = true\n"
          io << "footnotes = true\n"
          io << "mermaid = false        # Render ```mermaid code blocks as diagrams (loads mermaid.js)\n"
          io << "math = false           # Inline ($...$) and block ($$...$$) math (loads math_engine)\n"
          io << "math_engine = \"katex\"  # \"katex\" or \"mathjax\"\n\n"
        end

        str
      end
    end
  end
end
