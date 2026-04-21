# Initializer module for creating new Hwaro projects
#
# Creates the initial project structure with sample content,
# templates, and configuration based on the selected scaffold.

require "../config/options/init_options"
require "../utils/logger"
require "../services/scaffolds/registry"
require "../services/scaffolds/remote"
require "./defaults/agents_md"
require "./doctor"

module Hwaro
  module Services
    class Initializer
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
          options.minimal_config
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
      )
        scaffold = Scaffolds::Registry.get(scaffold_type)
        run_with_scaffold(target_path, force, skip_agents_md, skip_sample_content, skip_taxonomies, multilingual_languages, scaffold, agents_mode)
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
      )
        unless Dir.exists?(target_path)
          Dir.mkdir_p(target_path)
        end

        unless force || Dir.empty?(target_path)
          Logger.error "Directory '#{target_path}' is not empty."
          Logger.error "Use --force to overwrite."
          exit(1)
        end

        target_label = target_path == "." ? "current directory" : "'#{target_path}'"
        Logger.info "Initializing new Hwaro project in #{target_label}..."
        Logger.info "Using scaffold: #{scaffold.description}"

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
        config_content = if minimal_config
                           scaffold.minimal_config_content(skip_taxonomies)
                         elsif is_multilingual
                           create_multilingual_config(multilingual_languages, skip_taxonomies, scaffold)
                         else
                           scaffold.config_content(skip_taxonomies)
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

        # Auto-add missing optional config sections (commented out)
        unless minimal_config
          config_path = File.join(target_path, "config.toml")
          doctor = Services::Doctor.new(
            content_dir: File.join(target_path, "content"),
            config_path: config_path
          )
          added = doctor.fix_config(minimal: true)
          unless added.empty?
            Logger.info "Added #{added.size} optional config section(s) (commented out)."
          end
        end

        Logger.success "Done! Run `hwaro build` to generate the site."
      end

      private def create_scaffold_content(target_path : String, scaffold : Scaffolds::Base, skip_taxonomies : Bool)
        content_files = scaffold.content_files(skip_taxonomies)

        content_files.each do |relative_path, content|
          full_path = File.join(target_path, "content", relative_path)
          dir_path = File.dirname(full_path)

          # Create directory if it doesn't exist
          unless Dir.exists?(dir_path)
            create_directory(dir_path)
          end

          create_file(full_path, content)
        end
      end

      private def create_scaffold_templates(target_path : String, scaffold : Scaffolds::Base, skip_taxonomies : Bool)
        templates_dir = File.join(target_path, "templates")
        create_directory(templates_dir)

        # Create template files
        template_files = scaffold.template_files(skip_taxonomies)
        template_files.each do |relative_path, content|
          create_file(File.join(templates_dir, relative_path), content)
        end

        # Create shortcodes directory and files
        shortcodes_dir = File.join(templates_dir, "shortcodes")
        create_directory(shortcodes_dir)

        shortcode_files = scaffold.shortcode_files
        shortcode_files.each do |relative_path, content|
          full_path = File.join(templates_dir, relative_path)
          create_file(full_path, content)
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

        archetype_files.each do |relative_path, content|
          full_path = File.join(archetypes_dir, relative_path)
          dir_path = File.dirname(full_path)

          unless Dir.exists?(dir_path)
            create_directory(dir_path)
          end

          create_file(full_path, content)
        end
      end

      private def create_scaffold_static_files(target_path : String, scaffold : Scaffolds::Base)
        static_dir = File.join(target_path, "static")

        scaffold.static_files.each do |relative_path, content|
          full_path = File.join(static_dir, relative_path)
          dir_path = File.dirname(full_path)

          unless Dir.exists?(dir_path)
            create_directory(dir_path)
          end

          create_file(full_path, content)
        end
      end

      private def create_multilingual_content(
        target_path : String,
        languages : Array(String),
        skip_taxonomies : Bool,
        scaffold : Scaffolds::Base,
      )
        content_dir = File.join(target_path, "content")
        scaffold.multilingual_content_files(languages, skip_taxonomies).each do |relative_path, content|
          full_path = File.join(content_dir, relative_path)
          dir_path = File.dirname(full_path)
          create_directory(dir_path) unless Dir.exists?(dir_path)
          create_file(full_path, content)
        end
      end

      private def create_multilingual_config(
        languages : Array(String),
        skip_taxonomies : Bool,
        scaffold : Scaffolds::Base,
      ) : String
        default_lang = languages.first? || "en"

        lang_configs = languages.map_with_index do |lang, index|
          lang_name = language_display_name(lang)
          taxonomies_line = skip_taxonomies ? "" : "\n  taxonomies = [\"tags\", \"categories\"]"
          "  [languages.#{lang}]\n" \
          "  language_name = \"#{lang_name}\"\n" \
          "  weight = #{index + 1}\n" \
          "  generate_feed = true\n" \
          "  build_search_index = true#{taxonomies_line}"
        end.join("\n\n")

        taxonomies_config = if skip_taxonomies
                              ""
                            else
                              "# =============================================================================\n" \
                              "# Taxonomies\n" \
                              "# =============================================================================\n" \
                              "# Define content classification systems (tags, categories, etc.)\n\n" \
                              "[[taxonomies]]\n" \
                              "name = \"tags\"\n" \
                              "feed = true\n" \
                              "sitemap = false\n\n" \
                              "[[taxonomies]]\n" \
                              "name = \"categories\"\n" \
                              "paginate_by = 5\n\n" \
                              "[[taxonomies]]\n" \
                              "name = \"authors\"\n\n"
                            end

        String.build do |str|
          # Site basics
          str << "# =============================================================================\n"
          str << "# Site Configuration\n"
          str << "# =============================================================================\n\n"
          str << "title = \"My Hwaro Site\"\n"
          str << "description = \"Welcome to my new Hwaro site.\"\n"
          str << "base_url = \"http://localhost:3000\"\n\n"

          # Multilingual
          str << "# =============================================================================\n"
          str << "# Multilingual Configuration\n"
          str << "# =============================================================================\n\n"
          str << "default_language = \"#{default_lang}\"\n\n"
          str << "[languages]\n"
          str << lang_configs
          str << "\n\n"

          # Content & Processing
          str << "# =============================================================================\n"
          str << "# Plugins\n"
          str << "# =============================================================================\n"
          str << "# Configure content processors and extensions\n\n"
          str << "[plugins]\n"
          str << "processors = [\"markdown\"]\n\n"

          str << "# =============================================================================\n"
          str << "# Markdown Configuration\n"
          str << "# =============================================================================\n"
          str << "# Configure markdown parser behavior\n\n"
          str << "[markdown]\n"
          str << "safe = false          # If true, raw HTML in markdown will be stripped\n"
          str << "lazy_loading = false  # If true, automatically add loading=\"lazy\" to img tags\n"
          str << "emoji = false         # If true, convert emoji shortcodes (e.g. :smile:) to emoji characters\n\n"

          str << "# =============================================================================\n"
          str << "# Content Files\n"
          str << "# =============================================================================\n"
          str << "# Publish non-Markdown files from `content/` into the output directory.\n"
          str << "# Example: content/about/profile.jpg -> /about/profile.jpg\n\n"
          str << "[content.files]\n"
          str << "allow_extensions = [\"jpg\", \"jpeg\", \"png\", \"gif\", \"svg\", \"webp\"]\n"
          str << "# disallow_extensions = [\"psd\"]\n"
          str << "# disallow_paths = [\"private/**\", \"**/_*\"]\n\n"

          str << "# =============================================================================\n"
          str << "# Syntax Highlighting\n"
          str << "# =============================================================================\n"
          str << "# Code block syntax highlighting using Highlight.js\n\n"
          str << "[highlight]\n"
          str << "enabled = true\n"
          str << "theme = \"github\"          # Available: github, monokai, atom-one-dark, vs2015, etc.\n"
          str << "use_cdn = true            # Set to false to use local assets\n\n"

          str << "# =============================================================================\n"
          str << "# OpenGraph & Twitter Cards\n"
          str << "# =============================================================================\n"
          str << "# Default meta tags for social sharing\n"
          str << "# Page-level settings (front matter) override these defaults\n\n"
          str << "[og]\n"
          str << "default_image = \"/images/og-default.png\"   # Default image for social sharing\n"
          str << "type = \"article\"                           # OpenGraph type (website, article, etc.)\n"
          str << "twitter_card = \"summary_large_image\"       # Twitter card type (summary, summary_large_image)\n"
          str << "# twitter_site = \"@yourusername\"           # Twitter @username for the site\n"
          str << "# twitter_creator = \"@authorusername\"      # Twitter @username for content creator\n"
          str << "# fb_app_id = \"your_fb_app_id\"             # Facebook App ID (optional)\n\n"

          str << "# =============================================================================\n"
          str << "# Search Configuration\n"
          str << "# =============================================================================\n"
          str << "# Generates a search index for client-side search (e.g., Fuse.js)\n\n"
          str << "[search]\n"
          str << "enabled = true\n"
          str << "format = \"fuse_json\"\n"
          str << "fields = [\"title\", \"content\"]\n"
          str << "filename = \"search.json\"\n"
          str << "exclude = []              # Exclude paths or patterns from search index\n\n"

          str << "# =============================================================================\n"
          str << "# Pagination\n"
          str << "# =============================================================================\n"
          str << "# Enable pagination for section listing pages (e.g., /blog/).\n"
          str << "# You can override per section in `_index.md` with:\n"
          str << "# - paginate = 10\n"
          str << "# - pagination_enabled = true\n"
          str << "# - sort_by = \"date\" | \"title\" | \"weight\"\n"
          str << "# - reverse = false\n\n"
          str << "[pagination]\n"
          str << "enabled = false\n"
          str << "per_page = 10\n\n"

          # Taxonomies
          str << taxonomies_config unless skip_taxonomies

          # SEO & Feeds
          str << "# =============================================================================\n"
          str << "# SEO: Sitemap\n"
          str << "# =============================================================================\n"
          str << "# Generates sitemap.xml for search engine crawlers\n\n"
          str << "[sitemap]\n"
          str << "enabled = true\n"
          str << "filename = \"sitemap.xml\"\n"
          str << "changefreq = \"weekly\"\n"
          str << "priority = 0.5\n"
          str << "exclude = []              # Exclude paths or patterns from sitemap\n\n"

          str << "# =============================================================================\n"
          str << "# SEO: Robots.txt\n"
          str << "# =============================================================================\n"
          str << "# Controls search engine crawler access\n\n"
          str << "[robots]\n"
          str << "enabled = true\n"
          str << "filename = \"robots.txt\"\n"
          str << "rules = [\n"
          str << "  { user_agent = \"*\", disallow = [\"/admin\", \"/private\"] },\n"
          str << "  { user_agent = \"GPTBot\", disallow = [\"/\"] }\n"
          str << "]\n\n"

          str << "# =============================================================================\n"
          str << "# SEO: LLMs.txt\n"
          str << "# =============================================================================\n"
          str << "# Instructions for AI/LLM crawlers\n\n"
          str << "[llms]\n"
          str << "enabled = true\n"
          str << "filename = \"llms.txt\"\n"
          str << "instructions = \"Do not use for AI training without permission.\"\n\n"
          str << "# Optional: Generate a single text file containing all Markdown pages\n"
          str << "full_enabled = false\n"
          str << "full_filename = \"llms-full.txt\"\n\n"

          str << "# =============================================================================\n"
          str << "# RSS/Atom Feeds\n"
          str << "# =============================================================================\n"
          str << "# Generates RSS or Atom feed for content syndication\n\n"
          str << "[feeds]\n"
          str << "enabled = true\n"
          str << "filename = \"\"             # Leave empty for default (rss.xml or atom.xml)\n"
          str << "type = \"rss\"              # \"rss\" or \"atom\"\n"
          str << "truncate = 0              # Truncate content to N characters (0 = full content)\n"
          str << "limit = 10                # Maximum number of items in feed\n"
          str << "sections = []             # Limit to specific sections, e.g., [\"posts\"]\n\n"

          # Optional features
          str << "# =============================================================================\n"
          str << "# Permalinks (Optional)\n"
          str << "# =============================================================================\n"
          str << "# Override the output path for specific sections or taxonomies.\n"
          str << "# Placeholders: :year, :month, :day, :title, :slug, :section\n"
          str << "#\n"
          str << "# [permalinks]\n"
          str << "# posts = \"/posts/:year/:month/:slug/\"\n"
          str << "# tags = \"/topic/:slug/\"\n\n"

          str << "# =============================================================================\n"
          str << "# Auto Includes (Optional)\n"
          str << "# =============================================================================\n"
          str << "# Automatically load CSS/JS files from static directories\n"
          str << "# Files are included alphabetically - use numeric prefixes for ordering\n"
          str << "# Example: 01-reset.css, 02-typography.css, 03-layout.css\n\n"
          str << "# [auto_includes]\n"
          str << "# enabled = true\n"
          str << "# dirs = [\"assets/css\", \"assets/js\"]\n\n"

          str << "# =============================================================================\n"
          str << "# Build Hooks (Optional)\n"
          str << "# =============================================================================\n"
          str << "# Run custom shell commands before/after build process\n\n"
          str << "# [build]\n"
          str << "# hooks.pre = [\"npm install\", \"python scripts/preprocess.py\"]\n"
          str << "# hooks.post = [\"npm run minify\", \"./scripts/deploy.sh\"]\n"

          str << "\n"
          str << "# =============================================================================\n"
          str << "# Image Processing (Optional)\n"
          str << "# =============================================================================\n"
          str << "# Automatic image resizing and LQIP (Low-Quality Image Placeholder) generation.\n"
          str << "# Uses vendored stb libraries — no external tools required.\n"
          str << "#\n"
          str << "# Use resize_image() in templates:\n"
          str << "#   {% set img = resize_image(path=\"/images/hero.jpg\", width=1024) %}\n"
          str << "#   <img src=\"{{ img.url }}\"\n"
          str << "#        style=\"background-image: url({{ img.lqip }}); background-size: cover;\"\n"
          str << "#        loading=\"lazy\">\n\n"
          str << "# [image_processing]\n"
          str << "# enabled = true\n"
          str << "# widths = [320, 640, 1024, 1280]\n"
          str << "# quality = 85\n"
          str << "#\n"
          str << "# [image_processing.lqip]\n"
          str << "# enabled = true\n"
          str << "# width = 32             # Placeholder width in pixels (8-128)\n"
          str << "# quality = 20           # JPEG quality for placeholder (1-100, lower = smaller)\n\n"

          str << "# =============================================================================\n"
          str << "# Deployment (Optional)\n"
          str << "# =============================================================================\n"
          str << "# Configure deploy targets for `hwaro deploy`\n"
          str << "#\n"
          str << "# [deployment]\n"
          str << "# target = \"prod\"\n"
          str << "# source_dir = \"public\"\n"
          str << "# confirm = false\n"
          str << "# dryRun = false\n"
          str << "# maxDeletes = 256      # safety limit (-1 disables)\n"
          str << "#\n"
          str << "# [[deployment.targets]]\n"
          str << "# name = \"prod\"\n"
          str << "# url = \"file://./out\"\n"
          str << "#\n"
          str << "# [[deployment.targets]]\n"
          str << "# name = \"s3\"\n"
          str << "# url = \"s3://my-bucket\"\n"
          str << "# command = \"aws s3 sync {source}/ {url} --delete\"\n"
        end
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

      private def create_directory(path : String)
        if Dir.exists?(path)
          Logger.action :exist, path, :blue
        else
          Dir.mkdir_p(path)
          Logger.action :create, path
        end
      end

      private def create_file(path : String, content : String)
        if File.exists?(path)
          Logger.action :exist, path, :blue
        else
          File.write(path, content)
          Logger.action :create, path
        end
      end
    end
  end
end
