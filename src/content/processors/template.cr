# Template processor for Hwaro using Crinja (Jinja2) template engine
#
# This processor handles Jinja2-style templates with support for:
# - Variable interpolation: {{ variable }}
# - Control structures: {% if %}, {% for %}, {% endif %}, {% endfor %}
# - Filters: {{ value | filter }}
# - Template inheritance: {% extends %}, {% block %}
# - Includes: {% include %}
# - Macros: {% macro %}
#
# For full Jinja2 syntax documentation, see:
# https://jinja.palletsprojects.com/en/3.1.x/templates/
# https://github.com/straight-shoota/crinja

require "crinja"
require "./template/functions"

module Hwaro
  module Content
    module Processors
      # Context for template variable resolution
      class TemplateContext
        getter page : Models::Page
        getter config : Models::Config
        getter variables : Hash(String, Crinja::Value)

        def initialize(@page : Models::Page, @config : Models::Config)
          @variables = build_variables
        end

        # Add extra variables to the context
        def add(name : String, value : Crinja::Value)
          @variables[name] = value
        end

        def add(name : String, value : String)
          @variables[name] = Crinja::Value.new(value)
        end

        def add(name : String, value : Bool)
          @variables[name] = Crinja::Value.new(value)
        end

        def add(name : String, value : Int32 | Int64)
          @variables[name] = Crinja::Value.new(value)
        end

        def add(name : String, value : Nil)
          @variables[name] = Crinja::Value.new(nil)
        end

        def add(name : String, value : Array(String))
          @variables[name] = Crinja::Value.new(value.map { |v| Crinja::Value.new(v) })
        end

        def add(name : String, value : Hash(String, String))
          hash = {} of Crinja::Value => Crinja::Value
          value.each do |k, v|
            hash[Crinja::Value.new(k)] = Crinja::Value.new(v)
          end
          @variables[name] = Crinja::Value.new(hash)
        end

        private def build_variables : Hash(String, Crinja::Value)
          vars = {} of String => Crinja::Value

          # Page variables
          vars["page_title"] = Crinja::Value.new(@page.title)
          vars["page_description"] = Crinja::Value.new(@page.description || @config.description || "")
          vars["page_url"] = Crinja::Value.new(@page.url)
          vars["page_section"] = Crinja::Value.new(@page.section)
          vars["page_date"] = Crinja::Value.new(@page.date.try(&.to_s("%Y-%m-%d")) || "")
          vars["page_image"] = Crinja::Value.new(@page.image || @config.og.default_image || "")
          vars["taxonomy_name"] = Crinja::Value.new(@page.taxonomy_name || "")
          vars["taxonomy_term"] = Crinja::Value.new(@page.taxonomy_term || "")

          # Page object with boolean properties
          page_obj = {
            "title"       => Crinja::Value.new(@page.title),
            "description" => Crinja::Value.new(@page.description || ""),
            "url"         => Crinja::Value.new(@page.url),
            "section"     => Crinja::Value.new(@page.section),
            "date"        => Crinja::Value.new(@page.date.try(&.to_s("%Y-%m-%d")) || ""),
            "image"       => Crinja::Value.new(@page.image || ""),
            "draft"       => Crinja::Value.new(@page.draft),
            "toc"         => Crinja::Value.new(@page.toc),
            "render"      => Crinja::Value.new(@page.render),
            "is_index"    => Crinja::Value.new(@page.is_index),
            "generated"   => Crinja::Value.new(@page.generated),
            "in_sitemap"  => Crinja::Value.new(@page.in_sitemap),
          }
          vars["page"] = Crinja::Value.new(page_obj)

          # Site variables
          vars["site_title"] = Crinja::Value.new(@config.title)
          vars["site_description"] = Crinja::Value.new(@config.description || "")
          vars["base_url"] = Crinja::Value.new(@config.base_url)

          # Site object
          site_obj = {
            "title"       => Crinja::Value.new(@config.title),
            "description" => Crinja::Value.new(@config.description || ""),
            "base_url"    => Crinja::Value.new(@config.base_url),
          }
          vars["site"] = Crinja::Value.new(site_obj)

          # Config object (for advanced use)
          config_obj = {
            "title"       => Crinja::Value.new(@config.title),
            "description" => Crinja::Value.new(@config.description || ""),
            "base_url"    => Crinja::Value.new(@config.base_url),
          }
          vars["config"] = Crinja::Value.new(config_obj)

          # Section variables (basic, will be enriched by builder with actual section data)
          vars["section_title"] = Crinja::Value.new("")
          vars["section_description"] = Crinja::Value.new("")
          vars["section_list"] = Crinja::Value.new("")
          section_obj = {
            "title"       => Crinja::Value.new(""),
            "description" => Crinja::Value.new(""),
            "pages"       => Crinja::Value.new([] of Crinja::Value),
            "list"        => Crinja::Value.new(""),
          }
          vars["section"] = Crinja::Value.new(section_obj)

          # TOC variables (basic, will be enriched by builder with actual TOC data)
          vars["toc"] = Crinja::Value.new("")
          toc_obj = {
            "html" => Crinja::Value.new(""),
          }
          vars["toc_obj"] = Crinja::Value.new(toc_obj)

          # Time-related variables
          now = Time.local
          vars["current_year"] = Crinja::Value.new(now.year)
          vars["current_date"] = Crinja::Value.new(now.to_s("%Y-%m-%d"))
          vars["current_datetime"] = Crinja::Value.new(now.to_s("%Y-%m-%d %H:%M:%S"))

          vars
        end

        # Convert to Crinja variables hash
        def to_crinja_vars : Hash(String, Crinja::Value)
          @variables
        end
      end

      # Template Engine wrapper for Crinja
      class TemplateEngine
        getter env : Crinja

        def initialize
          @env = Crinja.new
          # Disable autoescape completely - Hwaro templates are trusted
          # and many variables contain pre-rendered HTML (og_tags, highlight_css, etc.)
          @env.config.autoescape.enabled_extensions = [] of String
          @env.config.autoescape.default = false
          register_custom_filters
          register_custom_tests
          register_custom_functions
        end

        # Set the template loader
        def loader=(loader : Crinja::Loader)
          @env.loader = loader
        end

        # Render a template string with the given context
        def render(template_string : String, context : TemplateContext) : String
          template = @env.from_string(template_string)
          template.render(context.to_crinja_vars)
        end

        # Render a template string with raw hash
        def render(template_string : String, variables : Hash(String, Crinja::Value)) : String
          template = @env.from_string(template_string)
          template.render(variables)
        end

        # Load and render a template by name
        def render_template(template_name : String, context : TemplateContext) : String
          template = @env.get_template(template_name)
          template.render(context.to_crinja_vars)
        end

        # Load and render a template by name with raw hash
        def render_template(template_name : String, variables : Hash(String, Crinja::Value)) : String
          template = @env.get_template(template_name)
          template.render(variables)
        end

        # Register custom filters specific to Hwaro
        private def register_custom_filters
          # Date formatting filter
          @env.filters["date"] = Crinja.filter({format: "%Y-%m-%d"}) do
            value = target.raw
            format = arguments["format"].as_s

            case value
            when Time
              value.to_s(format)
            when String
              # Try to parse the string as a date
              begin
                Time.parse(value, "%Y-%m-%d", Time::Location::UTC).to_s(format)
              rescue
                value
              end
            else
              value.to_s
            end
          end

          # Truncate words filter
          @env.filters["truncate_words"] = Crinja.filter({length: 50, end: "..."}) do
            text = target.to_s
            length = arguments["length"].as_number.to_i
            ending = arguments["end"].as_s

            words = text.split(/\s+/)
            if words.size > length
              words[0...length].join(" ") + ending
            else
              text
            end
          end

          # Slugify filter
          @env.filters["slugify"] = Crinja.filter do
            text = target.to_s
            text.downcase
              .gsub(/[^\w\s-]/, "")
              .gsub(/[\s_-]+/, "-")
              .strip("-")
          end

          # Absolute URL filter
          @env.filters["absolute_url"] = Crinja.filter do
            url = target.to_s
            base_url = env.resolve("base_url").to_s

            if url.starts_with?("http://") || url.starts_with?("https://")
              url
            elsif url.starts_with?("/")
              base_url.rstrip("/") + url
            else
              base_url.rstrip("/") + "/" + url
            end
          end

          # Relative URL filter (for base_url prefix)
          @env.filters["relative_url"] = Crinja.filter do
            url = target.to_s
            base_url = env.resolve("base_url").to_s

            if url.starts_with?("/")
              base_url.rstrip("/") + url
            else
              url
            end
          end

          # Strip HTML tags filter
          @env.filters["strip_html"] = Crinja.filter do
            target.to_s.gsub(/<[^>]*>/, "")
          end

          # Markdownify filter (simple - for inline markdown)
          @env.filters["markdownify"] = Crinja.filter do
            Markd.to_html(target.to_s)
          end

          # XML escape filter
          @env.filters["xml_escape"] = Crinja.filter do
            target.to_s
              .gsub("&", "&amp;")
              .gsub("<", "&lt;")
              .gsub(">", "&gt;")
              .gsub("\"", "&quot;")
              .gsub("'", "&apos;")
          end

          # JSON encode filter
          @env.filters["jsonify"] = Crinja.filter do
            target.to_s.to_json
          end

          # Array where filter (filter array by property value)
          @env.filters["where"] = Crinja.filter({attribute: nil, value: nil}) do
            result = begin
              arr = target.as_a
              attr = arguments["attribute"].to_s
              val = arguments["value"]

              filtered = arr.select do |item|
                begin
                  item_hash = item.as_h
                  item_val = item_hash[Crinja::Value.new(attr)]?
                  item_val == val
                rescue
                  false
                end
              end
              Crinja::Value.new(filtered)
            rescue
              Crinja::Value.new([] of Crinja::Value)
            end
            result
          end

          # Array sort_by filter
          @env.filters["sort_by"] = Crinja.filter({attribute: nil, reverse: false}) do
            result = begin
              arr = target.as_a
              attr = arguments["attribute"].to_s
              reverse = arguments["reverse"].truthy?

              sorted = arr.sort_by do |item|
                begin
                  item_hash = item.as_h
                  item_hash[Crinja::Value.new(attr)]?.try(&.to_s) || ""
                rescue
                  ""
                end
              end

              sorted = sorted.reverse if reverse
              Crinja::Value.new(sorted)
            rescue
              Crinja::Value.new([] of Crinja::Value)
            end
            result
          end

          # Group by filter
          @env.filters["group_by"] = Crinja.filter({attribute: nil}) do
            result = begin
              arr = target.as_a
              attr = arguments["attribute"].to_s
              groups = {} of String => Array(Crinja::Value)

              arr.each do |item|
                begin
                  item_hash = item.as_h
                  key = item_hash[Crinja::Value.new(attr)]?.try(&.to_s) || ""
                  groups[key] ||= [] of Crinja::Value
                  groups[key] << item
                rescue
                  # Skip non-hash items
                end
              end

              group_result = groups.map do |key, items|
                {
                  "grouper" => Crinja::Value.new(key),
                  "list"    => Crinja::Value.new(items),
                }
              end

              Crinja::Value.new(group_result.map { |h| Crinja::Value.new(h) })
            rescue
              Crinja::Value.new([] of Crinja::Value)
            end
            result
          end

          # Split filter - split string by separator
          @env.filters["split"] = Crinja.filter({pat: ","}) do
            text = target.to_s
            separator = arguments["pat"].to_s
            parts = text.split(separator).map { |s| Crinja::Value.new(s.strip) }
            Crinja::Value.new(parts)
          end

          # Safe filter - mark content as safe (no escaping)
          # In Crinja, we return a SafeString to prevent auto-escaping
          @env.filters["safe"] = Crinja.filter do
            Crinja::Value.new(Crinja::SafeString.new(target.to_s))
          end

          # Trim filter - remove leading/trailing whitespace
          @env.filters["trim"] = Crinja.filter do
            target.to_s.strip
          end

          # Default filter - provide default value if empty/nil
          @env.filters["default"] = Crinja.filter({value: ""}) do
            val = target.to_s
            if val.empty?
              arguments["value"].to_s
            else
              val
            end
          end
        end

        # Register custom tests
        private def register_custom_tests
          # Test if a string starts with a prefix
          # Usage: {% if page_url is startswith("/blog/") %}
          @env.tests["startswith"] = Crinja.test do
            prefix = arguments.varargs.first?.try(&.to_s) || ""
            target.to_s.starts_with?(prefix)
          end

          # Test if a string ends with a suffix
          # Usage: {% if page_title is endswith("!") %}
          @env.tests["endswith"] = Crinja.test do
            suffix = arguments.varargs.first?.try(&.to_s) || ""
            target.to_s.ends_with?(suffix)
          end

          # Test if a string contains a substring
          # Usage: {% if page_url is containing("products") %}
          @env.tests["containing"] = Crinja.test do
            substring = arguments.varargs.first?.try(&.to_s) || ""
            target.to_s.includes?(substring)
          end

          # Test if value is empty (string, array, hash)
          @env.tests["empty"] = Crinja.test do
            value = target.raw
            case value
            when String
              value.empty?
            when Array
              value.empty?
            when Hash
              value.empty?
            when Nil
              true
            else
              false
            end
          end

          # Test if value is present (not empty and not nil)
          @env.tests["present"] = Crinja.test do
            value = target.raw
            case value
            when String
              !value.empty?
            when Array
              !value.empty?
            when Hash
              !value.empty?
            when Nil
              false
            else
              true
            end
          end

          regex_cache = {} of String => Regex
          regex_mutex = Mutex.new

          # Test if a string matches a regex
          # Usage: {% if asset is matching("[.](jpg|png)$") %}
          @env.tests["matching"] = Crinja.test do
            regex_str = arguments.varargs.first?.try(&.to_s) || ""
            begin
              regex = regex_mutex.synchronize do
                regex_cache[regex_str] ||= Regex.new(regex_str)
              end
              target.to_s.matches?(regex)
            rescue
              false
            end
          end
        end

        # Register custom functions
        private def register_custom_functions
          Template::Functions.register(@env)
        end
      end

      # Template processor using Crinja
      # This module provides a singleton-like interface for template processing
      module Template
        @@engine : TemplateEngine?

        # Get or create the template engine
        def self.engine : TemplateEngine
          @@engine ||= TemplateEngine.new
        end

        # Reset the engine (useful for testing or reconfiguration)
        def self.reset_engine
          @@engine = nil
        end

        # Set custom loader for the engine
        def self.set_loader(loader : Crinja::Loader)
          engine.loader = loader
        end

        # Set loader from templates directory path
        def self.set_loader(templates_path : String)
          engine.loader = Crinja::Loader::FileSystemLoader.new(templates_path)
        end

        # Process a template string with context
        def self.process(content : String, context : TemplateContext) : String
          engine.render(content, context)
        end

        # Process a template string with raw variables hash
        def self.process(content : String, variables : Hash(String, Crinja::Value)) : String
          engine.render(content, variables)
        end

        # Render a named template from the loader
        def self.render_template(template_name : String, context : TemplateContext) : String
          engine.render_template(template_name, context)
        end

        # Create a context for the given page and config
        def self.create_context(page : Models::Page, config : Models::Config) : TemplateContext
          TemplateContext.new(page, config)
        end
      end
    end
  end
end
