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
      end
    end
  end
end
