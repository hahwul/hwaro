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

require "csv"
require "crinja"
require "./filters/*"
require "../../utils/crinja_utils"

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

        # Add a pre-built Crinja::Value to the context
        def add(name : String, value : Crinja::Value)
          @variables[name] = value
        end

        # Add a scalar value (String, Bool, Int, Nil) to the context
        def add(name : String, value : String | Bool | Int32 | Int64 | Nil)
          @variables[name] = Crinja::Value.new(value)
        end

        # Add an array of strings to the context
        def add(name : String, value : Array(String))
          @variables[name] = Crinja::Value.new(value.map { |v| Crinja::Value.new(v) })
        end

        # Add a string-keyed hash to the context
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

          # Site object (also available as "config" for advanced use)
          site_obj = {
            "title"       => Crinja::Value.new(@config.title),
            "description" => Crinja::Value.new(@config.description || ""),
            "base_url"    => Crinja::Value.new(@config.base_url),
          }
          site_value = Crinja::Value.new(site_obj)
          vars["site"] = site_value
          vars["config"] = site_value

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
          Filters::DateFilters.register(@env)
          Filters::StringFilters.register(@env)
          Filters::UrlFilters.register(@env)
          Filters::HtmlFilters.register(@env)
          Filters::CollectionFilters.register(@env)
          Filters::MathFilters.register(@env)
          Filters::I18nFilters.register(@env)
          Filters::MiscFilters.register(@env)
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
          max_regex_cache_size = 256

          # Test if a string matches a regex
          # Usage: {% if asset is matching("[.](jpg|png)$") %}
          @env.tests["matching"] = Crinja.test do
            regex_str = arguments.varargs.first?.try(&.to_s) || ""
            begin
              regex = regex_mutex.synchronize do
                # Evict oldest entry when cache is full
                if regex_cache.size >= max_regex_cache_size && !regex_cache.has_key?(regex_str)
                  regex_cache.delete(regex_cache.first_key)
                end
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
          # now() function - returns current time
          @env.functions["now"] = Crinja.function({format: nil}) do
            format = arguments["format"]
            time = Time.local

            if format.none?
              Crinja::Value.new(time.to_s("%Y-%m-%d %H:%M:%S"))
            else
              Crinja::Value.new(time.to_s(format.to_s))
            end
          end

          # url_for() function - generate URL for a path
          @env.functions["url_for"] = Crinja.function({path: ""}) do
            path = arguments["path"].to_s
            base_url = env.resolve("base_url").to_s

            if path.starts_with?("/")
              Crinja::Value.new(base_url.rstrip("/") + path)
            else
              Crinja::Value.new(base_url.rstrip("/") + "/" + path)
            end
          end

          # get_url() function - alias for url_for to match
          @env.functions["get_url"] = @env.functions["url_for"]

          # get_page() function - get page data by path
          # Usage: {% set about = get_page(path="about.md") %}
          #        {{ about.title }}
          @env.functions["get_page"] = Crinja.function({path: ""}) do
            path_arg = arguments["path"].to_s

            # Optimised O(1) lookup
            pages_map = env.resolve("__pages_by_path__")
            if !pages_map.raw.nil? && pages_map.raw.is_a?(Hash)
              raw_map = pages_map.raw.as(Hash)
              if found = raw_map[path_arg]?
                return found
              elsif found = raw_map["/#{path_arg.chomp(".md")}/"]?
                return found
              end
              # If map is present but page not found, return nil (miss)
              # This avoids falling back to linear search on miss when we have the index.
              return Crinja::Value.new(nil)
            end

            # Fallback to linear search O(N) if map is not available
            pages_val = env.resolve("__all_pages__")
            result = Crinja::Value.new(nil)

            raw_pages = pages_val.raw
            if raw_pages.is_a?(Array)
              raw_pages.each do |page_val|
                # Handle Crinja::Value wrapping a Hash
                raw_page = page_val.raw
                if raw_page.is_a?(Hash)
                  page_path = raw_page["path"]?.try(&.to_s) || ""
                  page_url = raw_page["url"]?.try(&.to_s) || ""

                  if page_path == path_arg || page_url == path_arg || page_url == "/#{path_arg.chomp(".md")}/"
                    result = page_val
                    break
                  end
                end
              end
            end

            result
          end

          # get_section() function - get section data by path
          # Usage: {% set blog = get_section(path="blog/_index.md") %}
          #        {% for page in blog.pages %}
          @env.functions["get_section"] = Crinja.function({path: ""}) do
            path_arg = arguments["path"].to_s

            # Optimised O(1) lookup via __sections_by_key__ map
            sections_map = env.resolve("__sections_by_key__")
            if !sections_map.raw.nil? && sections_map.raw.is_a?(Hash)
              raw_map = sections_map.raw.as(Hash)
              found = raw_map[path_arg]? || raw_map["/#{path_arg}/"]?
              found || Crinja::Value.new(nil)
            else
              # Fallback to linear search O(N) if map is not available
              sections_val = env.resolve("__all_sections__")
              result = Crinja::Value.new(nil)

              raw_sections = sections_val.raw
              if raw_sections.is_a?(Array)
                raw_sections.each do |section_val|
                  if section_val.is_a?(Hash)
                    section_path = section_val["path"]?.try(&.to_s) || ""
                    section_name = section_val["name"]?.try(&.to_s) || ""
                    section_url = section_val["url"]?.try(&.to_s) || ""

                    if section_path == path_arg || section_name == path_arg || section_url == "/#{path_arg}/"
                      result = Crinja::Value.new(section_val)
                      break
                    end
                  end
                end
              end

              result
            end
          end

          # get_taxonomy() function - get taxonomy terms and their pages
          # Usage: {% set tags = get_taxonomy(kind="tags") %}
          #        {% for term in tags.items %}
          @env.functions["get_taxonomy"] = Crinja.function({kind: ""}) do
            kind = arguments["kind"].to_s
            taxonomies_val = env.resolve("__taxonomies__")

            result = Crinja::Value.new(nil)

            raw_taxonomies = taxonomies_val.raw
            if raw_taxonomies.is_a?(Hash)
              if taxonomy_val = raw_taxonomies[kind]?
                result = Crinja::Value.new(taxonomy_val)
              end
            end

            result
          end

          # get_taxonomy_url() function - get URL for a taxonomy term
          # Usage: {{ get_taxonomy_url(kind="tags", term="crystal") }}
          @env.functions["get_taxonomy_url"] = Crinja.function({kind: "", term: ""}) do
            kind = arguments["kind"].to_s
            term = arguments["term"].to_s
            base_url = env.resolve("base_url").to_s

            # Generate slug from term (use TextUtils for consistency with taxonomy pages)
            slug = Utils::TextUtils.slugify(term)

            url = "/#{kind}/#{slug}/"
            Crinja::Value.new(base_url.rstrip("/") + url)
          end

          # resize_image() function - returns URL to a resized image variant
          # Usage: {{ resize_image(path="/images/photo.jpg", width=800).url }}
          # Returns object with:
          #   - url: URL to the resized variant (or original if not available)
          #   - width: requested width (0 if not specified)
          #   - height: requested height (0 if not specified)
          # Note: actual output dimensions depend on aspect ratio preservation.
          @env.functions["resize_image"] = Crinja.function({path: "", width: 0, height: 0}) do
            path = arguments["path"].to_s
            width = Math.max(0, arguments["width"].as_number.to_i)
            height = Math.max(0, arguments["height"].as_number.to_i)

            base_url = env.resolve("base_url").to_s

            # Normalize path to start with /
            normalized = path.starts_with?("/") ? path : "/#{path}"

            # Try to find a resized variant from the image hooks map
            resized_url = if width > 0
                            Content::Hooks::ImageHooks.find_closest(normalized, width)
                          end

            final_url = if resized = resized_url
                          base_url.rstrip("/") + resized
                        else
                          base_url.rstrip("/") + normalized
                        end

            Crinja::Value.new({
              "url"    => Crinja::Value.new(final_url),
              "width"  => Crinja::Value.new(width),
              "height" => Crinja::Value.new(height),
            })
          end

          # load_data() function - load data from JSON/TOML/YAML files
          # Usage: {% set data = load_data(path="data/menu.json") %}
          @env.functions["load_data"] = Crinja.function({path: ""}) do
            path = arguments["path"].to_s

            result = Crinja::Value.new(nil)

            begin
              # Restrict file access to the project directory (cwd)
              # to prevent reading arbitrary files via malicious templates.
              # Resolve symlinks BEFORE boundary check to prevent TOCTOU attacks.
              project_root = File.realpath(Dir.current)
              resolved = File.expand_path(path, project_root)
              resolved = File.realpath(resolved) rescue nil

              if resolved &&
                 (resolved == project_root || resolved.starts_with?(project_root + "/")) &&
                 File.exists?(resolved) && File.file?(resolved)
                content = File.read(resolved)

                if path.ends_with?(".json")
                  # Parse JSON
                  json_data = JSON.parse(content)
                  result = json_to_crinja(json_data)
                elsif path.ends_with?(".toml")
                  # Parse TOML
                  toml_data = TOML.parse(content)
                  result = toml_to_crinja(toml_data)
                elsif path.ends_with?(".yaml") || path.ends_with?(".yml")
                  # Parse YAML
                  yaml_data = YAML.parse(content)
                  result = yaml_to_crinja(yaml_data)
                elsif path.ends_with?(".csv")
                  # Parse CSV using stdlib parser (handles quoted fields correctly)
                  csv_data = CSV.parse(content).map do |row|
                    Crinja::Value.new(row.map { |cell| Crinja::Value.new(cell.strip) })
                  end
                  result = Crinja::Value.new(csv_data)
                else
                  ext = File.extname(path)
                  Logger.debug "load_data('#{path}'): unsupported file type '#{ext}' (supported: .json, .toml, .yaml, .yml, .csv)"
                end
              end
            rescue ex
              Logger.debug "load_data('#{path}'): #{ex.message}"
              result = Crinja::Value.new(nil)
            end

            result
          end

          # asset() function - resolve asset path from pipeline manifest
          # Usage: {{ asset(name="main.css") }}
          # Returns fingerprinted path if asset pipeline is enabled,
          # otherwise returns the path as-is under base_url.
          @env.functions["asset"] = Crinja.function({name: ""}) do
            asset_name = arguments["name"].to_s
            manifest = Content::Hooks::AssetHooks.manifest
            base_url = env.resolve("base_url").to_s.rstrip("/")

            if resolved = manifest[asset_name]?
              Crinja::Value.new(base_url + resolved)
            else
              # Fallback: return path under base_url as-is
              path = asset_name.starts_with?("/") ? asset_name : "/#{asset_name}"
              Crinja::Value.new(base_url + path)
            end
          end

          # asset_url is an alias for asset
          @env.functions["asset_url"] = @env.functions["asset"]

          # env() function - read environment variables in templates
          # Usage: {{ env("ANALYTICS_ID") }}
          #        {{ env("API_KEY", default="none") }}
          @env.functions["env"] = Crinja.function({name: "", default: nil}) do
            var_name = arguments["name"].to_s
            default_val = arguments["default"]
            has_default = !default_val.none?

            env_value = ENV[var_name]?

            if has_default
              # env("VAR", default="x") — use default when unset or empty
              # (aligned with ${VAR:-x} config semantics)
              if env_value && !env_value.empty?
                Crinja::Value.new(env_value)
              else
                default_val
              end
            elsif !env_value.nil?
              # env("VAR") — substitute if set (even empty)
              Crinja::Value.new(env_value)
            else
              Logger.warn "Environment variable '#{var_name}' is not set (referenced in template)"
              Crinja::Value.new("")
            end
          end
        end

        private def json_to_crinja(json : JSON::Any) : Crinja::Value
          Utils::CrinjaUtils.from_json(json)
        end

        private def toml_to_crinja(toml : TOML::Table) : Crinja::Value
          Utils::CrinjaUtils.from_toml(toml)
        end

        private def yaml_to_crinja(yaml : YAML::Any) : Crinja::Value
          Utils::CrinjaUtils.from_yaml(yaml)
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
