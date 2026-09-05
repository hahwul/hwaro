require "../config_snippets"

module Hwaro
  module Services
    module Defaults
      class ConfigSamples
        # The `[[taxonomies]]` sample appended to `config` unless skipped.
        TAXONOMIES_SAMPLE = <<-TOML
          # Taxonomies (root level configuration)
          [[taxonomies]]
          name = "tags"
          feed = true
          sitemap = false

          [[taxonomies]]
          name = "categories"
          paginate_by = 5

          [[taxonomies]]
          name = "authors"
          TOML

        def self.config(skip_taxonomies : Bool = false) : String
          taxonomies = skip_taxonomies ? "" : "\n\n" + TAXONOMIES_SAMPLE
          <<-CONTENT
            title = "My Hwaro Site"
            description = "Welcome to my new Hwaro site."
            base_url = "http://localhost:3000"

            [search]
            enabled = true
            format = "fuse_json"
            fields = ["title", "content"]
            filename = "search.json"

            [sitemap]
            enabled = true
            filename = "sitemap.xml"
            changefreq = "weekly"
            priority = 0.5

            [robots]
            enabled = true
            filename = "robots.txt"
            rules = [
              { user_agent = "*", disallow = ["/admin", "/private"] }
            ]

            [llms]
            enabled = true
            filename = "llms.txt"
            instructions = "Do not use for AI training without permission."
            # Optional: Generate a single text file containing all Markdown pages
            full_enabled = false
            full_filename = "llms-full.txt"

            [feeds]
            enabled = true
            filename = ""   # Default: rss.xml or atom.xml
            type = "rss"
            truncate = 0
            limit = 10
            sections = []   # Optional: e.g. ["blog"]
            default_language_only = true  # true: main feed = default language only, false: all languages

            #{ConfigSnippets.og_auto_image}

            # Series
            [series]
            enabled = true

            # Related Posts
            [related]
            enabled = true
            limit = 5
            taxonomies = ["tags"]

            # Git Metadata - page.git + `updated` fallback from commit history
            # [git]
            # enabled = true

            # Plugins Configuration
            [plugins]
            processors = ["markdown"]  # List of enabled processors

            # Build Hooks - Run custom commands before/after build
            # [build]
            # hooks.pre = ["npm install", "python scripts/preprocess.py"]
            # hooks.post = ["npm run minify", "./scripts/deploy.sh"]

            # Deployment - Configure targets for `hwaro deploy`
            # [deployment]
            # target = "prod"          # default target name (optional)
            # source_dir = "public"    # default: public
            # confirm = false          # ask before deploying
            # dryRun = false           # show plan only
            # maxDeletes = 256         # safety limit (-1 disables)
            #
            # [[deployment.targets]]
            # name = "prod"
            # url = "file://./out"
            #
            # [[deployment.targets]]
            # name = "s3"
            # url = "s3://my-bucket"
            # command = "aws s3 sync {source}/ {url} --delete"#{taxonomies}
            CONTENT
        end

        def self.config_without_taxonomies : String
          config(skip_taxonomies: true)
        end

        # Generate config with multilingual support
        def self.config_multilingual(languages : Array(String), skip_taxonomies : Bool = false) : String
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
                                "\n# Taxonomies (root level configuration)\n" \
                                "[[taxonomies]]\n" \
                                "name = \"tags\"\n" \
                                "feed = true\n" \
                                "sitemap = false\n\n" \
                                "[[taxonomies]]\n" \
                                "name = \"categories\"\n" \
                                "paginate_by = 5\n\n" \
                                "[[taxonomies]]\n" \
                                "name = \"authors\"\n"
                              end

          String.build do |str|
            str << "title = \"My Hwaro Site\"\n"
            str << "description = \"Welcome to my new Hwaro site.\"\n"
            str << "base_url = \"http://localhost:3000\"\n\n"
            str << "# Multilingual Configuration\n"
            str << "default_language = \"#{default_lang}\"\n\n"
            str << "[languages]\n"
            str << lang_configs
            str << "\n\n"
            str << "[search]\n"
            str << "enabled = true\n"
            str << "format = \"fuse_json\"\n"
            str << "fields = [\"title\", \"content\"]\n"
            str << "filename = \"search.json\"\n\n"
            str << "[sitemap]\n"
            str << "enabled = true\n"
            str << "filename = \"sitemap.xml\"\n"
            str << "changefreq = \"weekly\"\n"
            str << "priority = 0.5\n\n"
            str << "[robots]\n"
            str << "enabled = true\n"
            str << "filename = \"robots.txt\"\n"
            str << "rules = [\n"
            str << "  { user_agent = \"*\", disallow = [\"/admin\", \"/private\"] }\n"
            str << "]\n\n"
            str << "[llms]\n"
            str << "enabled = true\n"
            str << "filename = \"llms.txt\"\n"
            str << "instructions = \"Do not use for AI training without permission.\"\n\n"
            str << "[feeds]\n"
            str << "enabled = true\n"
            str << "filename = \"\"   # Default: rss.xml or atom.xml\n"
            str << "type = \"rss\"\n"
            str << "truncate = 0\n"
            str << "limit = 10\n"
            str << "sections = []   # Optional: e.g. [\"blog\"]\n"
            str << "default_language_only = true  # true: main feed = default language only, false: all languages\n\n"
            str << ConfigSnippets.og_auto_image
            str << "# Series\n"
            str << "[series]\n"
            str << "enabled = true\n\n"
            str << "# Related Posts\n"
            str << "[related]\n"
            str << "enabled = true\n"
            str << "limit = 5\n"
            str << "taxonomies = [\"tags\"]\n\n"
            str << "# Git Metadata - page.git + `updated` fallback from commit history\n"
            str << "# [git]\n"
            str << "# enabled = true\n\n"
            str << "# Plugins Configuration\n"
            str << "[plugins]\n"
            str << "processors = [\"markdown\"]  # List of enabled processors\n\n"
            str << "# Build Hooks - Run custom commands before/after build\n"
            str << "# [build]\n"
            str << "# hooks.pre = [\"npm install\", \"python scripts/preprocess.py\"]\n"
            str << "# hooks.post = [\"npm run minify\", \"./scripts/deploy.sh\"]\n"
            str << "\n"
            str << "# Deployment - Configure targets for `hwaro deploy`\n"
            str << "# [deployment]\n"
            str << "# target = \"prod\"          # default target name (optional)\n"
            str << "# source_dir = \"public\"    # default: public\n"
            str << "# confirm = false          # ask before deploying\n"
            str << "# dryRun = false           # show plan only\n"
            str << "# maxDeletes = 256         # safety limit (-1 disables)\n"
            str << "#\n"
            str << "# [[deployment.targets]]\n"
            str << "# name = \"prod\"\n"
            str << "# url = \"file://./out\"\n"
            str << "#\n"
            str << "# [[deployment.targets]]\n"
            str << "# name = \"s3\"\n"
            str << "# url = \"s3://my-bucket\"\n"
            str << "# command = \"aws s3 sync {source}/ {url} --delete\"\n"
            str << taxonomies_config
          end
        end

        # Get display name for language code
        private def self.language_display_name(code : String) : String
          Utils::TextUtils.language_display_name(code)
        end
      end
    end
  end
end
