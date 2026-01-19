module Hwaro
  module Services
    module Defaults
      class ConfigSamples
        def self.config : String
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
            { user_agent = "*", disallow = ["/admin", "/private"] },
            { user_agent = "GPTBot", disallow = ["/"] }
          ]

          [llms]
          enabled = true
          filename = "llms.txt"
          instructions = "Do not use for AI training without permission."

          [feeds]
          enabled = true
          filename = ""   # Default: rss.xml or atom.xml
          type = "rss"
          truncate = 0
          limit = 10
          sections = []   # Optional: e.g. ["blog"]

          # Plugins Configuration
          [plugins]
          processors = ["markdown"]  # List of enabled processors

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
          CONTENT
        end

        def self.config_without_taxonomies : String
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
            { user_agent = "*", disallow = ["/admin", "/private"] },
            { user_agent = "GPTBot", disallow = ["/"] }
          ]

          [llms]
          enabled = true
          filename = "llms.txt"
          instructions = "Do not use for AI training without permission."

          [feeds]
          enabled = true
          filename = ""   # Default: rss.xml or atom.xml
          type = "rss"
          truncate = 0
          limit = 10
          sections = []   # Optional: e.g. ["blog"]

          # Plugins Configuration
          [plugins]
          processors = ["markdown"]  # List of enabled processors
          CONTENT
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
            str << "  { user_agent = \"*\", disallow = [\"/admin\", \"/private\"] },\n"
            str << "  { user_agent = \"GPTBot\", disallow = [\"/\"] }\n"
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
            str << "sections = []   # Optional: e.g. [\"blog\"]\n\n"
            str << "# Plugins Configuration\n"
            str << "[plugins]\n"
            str << "processors = [\"markdown\"]  # List of enabled processors\n"
            str << taxonomies_config
          end
        end

        # Get display name for language code
        private def self.language_display_name(code : String) : String
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
      end
    end
  end
end
