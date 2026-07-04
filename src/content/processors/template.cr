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
require "../../utils/errors"

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
        def add(name : String, value : String | Bool | Int32 | Int64?)
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
            "html"    => Crinja::Value.new(""),
            "headers" => Crinja::Value.new([] of Crinja::Value),
          }
          vars["toc_obj"] = Crinja::Value.new(toc_obj)

          # SEO variables (basic defaults, enriched by builder with page-specific data)
          seo_obj = {
            "canonical_url"   => Crinja::Value.new(""),
            "og_type"         => Crinja::Value.new(""),
            "og_image"        => Crinja::Value.new(""),
            "twitter_card"    => Crinja::Value.new(""),
            "twitter_site"    => Crinja::Value.new(""),
            "twitter_creator" => Crinja::Value.new(""),
            "fb_app_id"       => Crinja::Value.new(""),
            "hreflang"        => Crinja::Value.new([] of Crinja::Value),
          }
          vars["seo"] = Crinja::Value.new(seo_obj)

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

        # Render a template string with the given context. Pass `name`/`filename`
        # when the string came from a file so Crinja errors report file:line:col.
        def render(template_string : String, context : TemplateContext, name : String = "", filename : String? = nil) : String
          template = Crinja::Template.new(template_string, @env, name, filename)
          template.render(context.to_crinja_vars)
        rescue ex : Crinja::Error
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_TEMPLATE,
            message: "Template error for #{context.page.path}: #{ex.message}",
            cause: ex,
          )
        end

        # Render a template string with raw hash. Pass `name`/`filename`
        # when the string came from a file so Crinja errors report file:line:col.
        def render(template_string : String, variables : Hash(String, Crinja::Value), name : String = "", filename : String? = nil) : String
          template = Crinja::Template.new(template_string, @env, name, filename)
          template.render(variables)
        rescue ex : Crinja::Error
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_TEMPLATE,
            message: "Template error: #{ex.message}",
            cause: ex,
          )
        end

        # Load and render a template by name
        def render_template(template_name : String, context : TemplateContext) : String
          template = @env.get_template(template_name)
          template.render(context.to_crinja_vars)
        rescue ex : Crinja::Error
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_TEMPLATE,
            message: "Template error in '#{template_name}' for #{context.page.path}: #{ex.message}",
            cause: ex,
          )
        end

        # Load and render a template by name with raw hash
        def render_template(template_name : String, variables : Hash(String, Crinja::Value)) : String
          template = @env.get_template(template_name)
          template.render(variables)
        rescue ex : Crinja::Error
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_TEMPLATE,
            message: "Template error in '#{template_name}': #{ex.message}",
            cause: ex,
          )
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
          Filters::MenuFilters.register(@env)
        end

        # Shared body for the `empty`/`present` Crinja tests: a value is empty
        # when it's an empty string/array/hash or nil.
        private def value_empty?(value : Crinja::Raw) : Bool
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
            value_empty?(target.raw)
          end

          # Test if value is present (not empty and not nil)
          @env.tests["present"] = Crinja.test do
            !value_empty?(target.raw)
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
            rescue ArgumentError
              false
            end
          end
        end

        # Register custom functions
        private def register_custom_functions
          register_now_function
          register_url_for_function
          register_lookup_functions
          register_image_function
          register_data_function
          register_asset_functions
          register_env_function
        end

        private def register_now_function
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
        end

        private def register_url_for_function
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
        end

        private def register_lookup_functions
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

          # get_menu() function - get a named menu's resolved entry tree.
          # Usage: {% for item in get_menu(name="main") %}
          # Resolves against the CURRENT page's language (falling back to
          # the site's default language), so the same template renders each
          # language's own menu — unlike `site.menus`, which is fixed to the
          # default language. Returns an empty array (not nil) for an unknown
          # or unregistered menu name, so `{% for %}` never errors.
          @env.functions["get_menu"] = Crinja.function({name: ""}) do
            menu_name = arguments["name"].to_s
            lang = env.resolve("page_language").to_s
            default_lang = env.resolve("_i18n_default_language").to_s

            menus_val = env.resolve("__menus__")
            result = Crinja::Value.new([] of Crinja::Value)

            raw_menus = menus_val.raw
            if raw_menus.is_a?(Hash)
              lang_menus = raw_menus[lang]?.try(&.raw)
              found = lang_menus[menu_name]? if lang_menus.is_a?(Hash)

              if !found && lang != default_lang
                default_menus = raw_menus[default_lang]?.try(&.raw)
                found = default_menus[menu_name]? if default_menus.is_a?(Hash)
              end

              result = found if found
            end

            result
          end

          # get_taxonomy_url() function - get URL for a taxonomy term
          # Usage: {{ get_taxonomy_url(kind="tags", term="crystal") }}
          @env.functions["get_taxonomy_url"] = Crinja.function({kind: "", term: ""}) do
            kind = arguments["kind"].to_s
            term = arguments["term"].to_s
            base_url = env.resolve("base_url").to_s

            # Resolve the slug from the disambiguated term→slug map built in
            # build_global_vars, so a collision (e.g. "C++"/"C#" → "c") links to
            # the SAME unique path the taxonomy generator wrote, not a shared
            # base slug. Fall back to safe_slugify when the map is absent or the
            # term is unknown — plain slugify("🎉") is "" → "/tags//" (a dead
            # double-slash link), so safe_slugify is the right fallback.
            slug = nil
            slugs_raw = env.resolve("__taxonomy_slugs__").raw
            if slugs_raw.is_a?(Hash)
              if kind_map = slugs_raw[kind]?
                kind_raw = kind_map.raw
                if kind_raw.is_a?(Hash)
                  if mapped = kind_raw[term]?
                    slug = mapped.to_s
                  end
                end
              end
            end
            slug ||= Utils::TextUtils.safe_slugify(term)

            url = "/#{kind}/#{slug}/"
            Crinja::Value.new(base_url.rstrip("/") + url)
          end
        end

        private def register_image_function
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

            # Normalize path to start with /. The resize/LQIP maps are keyed by
            # the decoded filesystem path, so decode any percent-encoding from
            # the incoming URL before the lookup; the returned variant is
            # re-encoded below so the emitted .url is a valid href.
            normalized = URI.decode(path.starts_with?("/") ? path : "/#{path}")

            # Try to find a resized variant from the image hooks map
            resized_url = if width > 0
                            Content::Hooks::ImageHooks.find_closest(normalized, width)
                          end

            final_url = if resized = resized_url
                          base_url.rstrip("/") + URI.encode_path(resized)
                        else
                          base_url.rstrip("/") + URI.encode_path(normalized)
                        end

            # Look up LQIP data
            lqip_data = Content::Hooks::ImageHooks.find_lqip(normalized)
            lqip_value = lqip_data.try { |d| d["lqip"]? } || ""
            dominant_color_value = lqip_data.try { |d| d["dominant_color"]? } || ""

            Crinja::Value.new({
              "url"            => Crinja::Value.new(final_url),
              "width"          => Crinja::Value.new(width),
              "height"         => Crinja::Value.new(height),
              "lqip"           => Crinja::Value.new(lqip_value),
              "dominant_color" => Crinja::Value.new(dominant_color_value),
            })
          end
        end

        # Memoized load_data results, shared across engine instances (each
        # parallel render worker gets its own env, so an instance cache would
        # miss on every worker). Keyed by resolved path; the stored mtime
        # invalidates naturally when the data file changes, so `serve`
        # sessions pick up edits. Mutex-guarded — workers call load_data
        # concurrently under -Dpreview_mt. Without this, a load_data() call
        # in a base layout re-read and re-parsed the file once per page.
        @@load_data_cache = {} of String => {Int64, Crinja::Value}
        @@load_data_mutex = Mutex.new

        private def register_data_function
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
              resolved = begin
                File.realpath(resolved)
              rescue File::Error
                nil
              end

              if resolved &&
                 (resolved == project_root || resolved.starts_with?(project_root + "/")) &&
                 (info = File.info?(resolved)) && info.file?
                # to_unix_ms (Int64) like the build cache — to_unix_ns is Int128
                mtime = info.modification_time.to_unix_ms

                # One lock across lookup + parse: data files are tiny, and it
                # also means N parallel workers cold-starting on the same
                # file parse it once instead of racing to parse in duplicate.
                result = @@load_data_mutex.synchronize do
                  cached = @@load_data_cache[resolved]?
                  if cached && cached[0] == mtime
                    cached[1]
                  elsif parsed = parse_data_content(path, File.read(resolved))
                    @@load_data_cache[resolved] = {mtime, parsed}
                    parsed
                  else
                    Crinja::Value.new(nil)
                  end
                end
              end
            rescue ex
              Logger.debug "load_data('#{path}'): #{ex.message}"
              result = Crinja::Value.new(nil)
            end

            result
          end
        end

        # Parse a data file's content by the extension carried on `path` (the
        # template-facing argument). Returns nil for unsupported types.
        private def parse_data_content(path : String, content : String) : Crinja::Value?
          if path.ends_with?(".json")
            json_to_crinja(JSON.parse(content))
          elsif path.ends_with?(".toml")
            toml_to_crinja(TOML.parse(content))
          elsif path.ends_with?(".yaml") || path.ends_with?(".yml")
            yaml_to_crinja(YAML.parse(content))
          elsif path.ends_with?(".csv")
            # Parse CSV using stdlib parser (handles quoted fields correctly)
            csv_data = CSV.parse(content).map do |row|
              Crinja::Value.new(row.map { |cell| Crinja::Value.new(cell.strip) })
            end
            Crinja::Value.new(csv_data)
          else
            Logger.debug "load_data('#{path}'): unsupported file type '#{File.extname(path)}' (supported: .json, .toml, .yaml, .yml, .csv)"
            nil
          end
        end

        private def register_asset_functions
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
        end

        private def register_env_function
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
