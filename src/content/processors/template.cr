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
        # when it's an empty string/array/hash, nil or undefined.
        private def value_empty?(value : Crinja::Raw) : Bool
          case value
          when String, Crinja::SafeString
            value.to_s.empty?
          when Array
            value.empty?
          when Hash
            value.empty?
          when Nil, Crinja::Undefined
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

          # Test if a string contains a substring, or a list/mapping an
          # element/key (the `in` operator's rules, not the list's text)
          # Usage: {% if page_url is containing("products") %}
          @env.tests["containing"] = Crinja.test do
            needle = arguments.varargs.first? || Crinja::Value.new("")
            if target.iterable?
              Crinja::Operator.member?(needle, target)
            else
              target.to_s.includes?(needle.to_s)
            end
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
              # Same guard as the `date` filter: a malformed format string
              # (`now(format="%")`) makes Crystal's `Time#to_s` raise a bare
              # `IndexError`, which is not a `Crinja::Error` and so kills the
              # build with `Index out of bounds` and no template file:line.
              Crinja::Value.new(Filters::DateFilters.format_time(time, format.to_s))
            end
          end
        end

        private def register_url_for_function
          # url_for() function - generate URL for a path
          @env.functions["url_for"] = Crinja.function({path: ""}) do
            path = arguments["path"].to_s
            base_url = env.resolve("base_url").to_s
            Crinja::Value.new(Filters::UrlFilters.absolutize(path, base_url))
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
              elsif found = raw_map["/#{path_arg.chomp(".markdown").chomp(".md")}/"]?
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

                  if page_path == path_arg || page_url == path_arg || page_url == "/#{path_arg.chomp(".markdown").chomp(".md")}/"
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

            # A section name can occur in every language variant. Resolve an
            # ambiguous name in the current page's language before falling
            # back to the default language or the legacy site-wide map.
            language_maps = env.resolve("__sections_by_key_by_lang__").raw
            if language_maps.is_a?(Hash)
              language = env.resolve("page_language").to_s
              default_language = env.resolve("_i18n_default_language").to_s
              languages = [] of String
              languages << language unless language.empty?
              languages << default_language unless default_language.empty? || languages.includes?(default_language)

              languages.each do |candidate|
                next unless candidate_map = language_maps[candidate]?
                next unless candidate_map.raw.is_a?(Hash)
                raw_candidate_map = candidate_map.raw.as(Hash)
                if found = raw_candidate_map[path_arg]? || raw_candidate_map["/#{path_arg}/"]?
                  return found
                end
              end
            end

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
            # Versioned page: its version's own menu set (`__menus_v__` is
            # {version name => {lang => menus}}, built by the render phase)
            # replaces the site-wide set, so registrations from another
            # version never leak into this page's nav.
            page_version = env.resolve("page_version")
            unless page_version.undefined? || page_version.raw.nil?
              versioned = env.resolve("__menus_v__").raw
              if versioned.is_a?(Hash) && (own = versioned[page_version.to_s]?)
                menus_val = own
              end
            end
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
            # A multilingual site writes `/<lang>/<taxonomy>/<slug>/` term pages
            # for every non-default language that enables the taxonomy. Prefer
            # the CURRENT page's language when such a page exists: the root
            # `/tags/<slug>/` either 404s (term present only in that language) or
            # lands the reader on the default language's listing.
            # `__taxonomy_lang_slugs__` only carries terms the generator actually
            # wrote, so a miss safely falls through to the root URL below.
            lang = env.resolve("page_language").to_s
            default_lang = env.resolve("_i18n_default_language").to_s
            lang_prefix = ""
            slug = nil

            if !lang.empty? && lang != default_lang
              lang_raw = env.resolve("__taxonomy_lang_slugs__").raw
              if lang_raw.is_a?(Hash) && (per_lang = lang_raw[lang]?)
                per_lang_raw = per_lang.raw
                if per_lang_raw.is_a?(Hash) && (kind_map = per_lang_raw[kind]?)
                  kind_raw = kind_map.raw
                  if kind_raw.is_a?(Hash) && (mapped = kind_raw[term]?)
                    slug = mapped.to_s
                    lang_prefix = "/#{lang}"
                  end
                end
              end
            end

            unless slug
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
            end
            slug ||= Utils::TextUtils.safe_slugify(term)

            url = "#{lang_prefix}/#{kind}/#{slug}/"
            Crinja::Value.new(base_url.rstrip("/") + url)
          end
        end

        private def register_image_function
          # resize_image() function - returns URL to a resized image variant
          # Usage: {{ resize_image(path="/images/photo.jpg", width=800).url }}
          # Returns object with:
          #   - url: URL to the resized variant (or original if not available)
          #   - width: the variant's actual width, falling back to the
          #     requested one when no variant exists (0 if not specified)
          #   - height: requested height (0 if not specified)
          # `width` is the variant's, not the request's: variants are never
          # upscaled, so `width=1024` against a 900px source resolves to the
          # 900px file — and the documented `<img width="{{ img.width }}">`
          # then told the browser 1024, laying out the image at the wrong
          # size. `height` stays the requested value: the resize map is
          # rebuilt from variant FILENAMES on warm builds (`_320w.png`), so a
          # real height is not recoverable without decoding every image.
          @env.functions["resize_image"] = Crinja.function({path: "", width: 0, height: 0}) do
            path = arguments["path"].to_s
            # Lenient coercion: shortcode arguments are always Strings, so a
            # `width="800"` forwarded from `{% img(width="800") %}` must resize
            # rather than raise Crinja::TypeError and abort the page.
            width = Utils::CrinjaUtils.to_count(arguments["width"])
            height = Utils::CrinjaUtils.to_count(arguments["height"])

            base_url = env.resolve("base_url").to_s

            # Normalize path to start with /. The resize/LQIP maps are keyed by
            # the decoded filesystem path, so decode any percent-encoding from
            # the incoming URL before the lookup; the returned variant is
            # re-encoded below so the emitted .url is a valid href.
            normalized = URI.decode(path.starts_with?("/") ? path : "/#{path}")

            # The variant set, width and LQIP colour all follow the SOURCE
            # image's bytes. An image no resize job covered (a missing file)
            # is recorded at its static/ location, so one that appears there
            # later re-renders the page too.
            if Content::Hooks::ImageHooks.processing_active?
              source = Content::Hooks::ImageHooks.source_path_for(normalized) || File.join("static", normalized)
              TemplateEngine.record_file_read(source)
            end

            # Try to find a resized variant from the image hooks map
            variant = if width > 0
                        Content::Hooks::ImageHooks.find_closest_variant(normalized, width)
                      end

            final_url = if resized = variant
                          base_url.rstrip("/") + URI.encode_path(resized[1])
                        else
                          base_url.rstrip("/") + URI.encode_path(normalized)
                        end
            actual_width = variant.try(&.[0]) || width

            # Look up LQIP data
            lqip_data = Content::Hooks::ImageHooks.find_lqip(normalized)
            lqip_value = lqip_data.try { |d| d["lqip"]? } || ""
            dominant_color_value = lqip_data.try { |d| d["dominant_color"]? } || ""

            Crinja::Value.new({
              "url"            => Crinja::Value.new(final_url),
              "width"          => Crinja::Value.new(actual_width),
              "height"         => Crinja::Value.new(height),
              "lqip"           => Crinja::Value.new(lqip_value),
              "dominant_color" => Crinja::Value.new(dominant_color_value),
            })
          end
        end

        # Inputs a render read from OUTSIDE the tracked tree, recorded so a
        # `--cache` build can tell when they move: `env()` names, `load_data()`
        # files and `resize_image()` source images. None of them is in any
        # cache key (they are read mid-render, per call), so a cached page kept
        # the old analytics ID / data row / image variant for as long as its
        # own source stayed untouched. Keys are `"env:NAME"` and `"file:PATH"`;
        # values are never stored here or anywhere — the build digests them.
        # Shared across engine instances and mutex-guarded: every parallel
        # render worker has its own env.
        @@render_reads = Set(String).new
        @@render_reads_mutex = Mutex.new

        ENV_READ_PREFIX  = "env:"
        FILE_READ_PREFIX = "file:"

        def self.record_render_read(key : String) : Nil
          @@render_reads_mutex.synchronize { @@render_reads << key }
        end

        # Record a file read by its project-relative path (the cache outlives
        # the checkout path: CI restores it under a different directory). A
        # path that escapes the project is not recorded — nothing reads it.
        def self.record_file_read(path : String) : Nil
          return if path.empty? || Hwaro::Utils::PathUtils.absolute?(path)
          normalized = Path.posix(path).normalize.to_s
          return if normalized == ".." || normalized.starts_with?("../")
          record_render_read(FILE_READ_PREFIX + normalized)
        end

        # Everything recorded since the last call, and start a new record.
        def self.take_render_reads : Set(String)
          @@render_reads_mutex.synchronize do
            taken = @@render_reads
            @@render_reads = Set(String).new
            taken
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

        # Drop every memoized load_data() result. Called at the start of each
        # build (Builder#run), so the memo only ever spans ONE build.
        #
        # The mtime key alone is not a proof of identity: it is millisecond
        # resolution, and a file rewritten inside one filesystem timestamp
        # tick (ext4 stamps with the kernel's coarse clock, 1-10ms; FAT/HFS+
        # are coarser still) keeps the previous mtime, so a same-size,
        # same-tick rewrite of `data/team.csv` was served from the memo —
        # the previous file's rows — even though the data digest had already
        # moved and forced the page to re-render. That is the flake in
        # "re-renders when a data/*.csv changes": in-process, the two builds
        # can land in the same tick. `hwaro serve` has the same exposure on
        # every rebuild. A build must see the disk as it is when it starts,
        # and within one build a data file cannot legitimately change, so
        # the memo's whole purpose (parse once per build, not once per page)
        # survives a per-build reset intact.
        def self.clear_load_data_cache : Nil
          @@load_data_mutex.synchronize do
            @@load_data_cache.clear
            # A new build (or serve rebuild) gets its warnings again — the
            # author may have fixed the path, or not, and needs to see which.
            @@load_data_warned.clear
          end
        end

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
              # Recorded before the existence check: a page rendered while the
              # file was missing changes once it appears.
              if relative = Hwaro::Utils::PathUtils.relative_path(resolved, project_root)
                TemplateEngine.record_file_read(relative) unless relative.empty?
              end
              resolved = begin
                File.realpath(resolved)
              rescue File::Error
                nil
              end

              if resolved &&
                 Hwaro::Utils::PathUtils.within?(resolved, project_root) &&
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
              elsif resolved && !Hwaro::Utils::PathUtils.within?(resolved, project_root)
                warn_load_data_once(path, "resolves outside the project directory and is refused")
              else
                warn_load_data_once(path, "is not a file (paths resolve against the project root)")
              end
            rescue ex
              warn_load_data_once(path, "could not be loaded: #{ex.message}")
              result = Crinja::Value.new(nil)
            end

            result
          end
        end

        # A `load_data()` miss used to render as a bare `none` (or an empty
        # loop) with nothing in the log — a typo'd path, a file dropped outside
        # the project, or a malformed data file were indistinguishable from an
        # intentionally empty dataset. Warn once per path per build: the
        # function runs for every page that calls it, and the same typo on a
        # 500-page site is one problem, not 500 lines.
        @@load_data_warned = Set(String).new

        private def warn_load_data_once(path : String, reason : String) : Nil
          first = @@load_data_mutex.synchronize { @@load_data_warned.add?(path) }
          Logger.warn "load_data(#{path.inspect}) #{reason}; the template receives none." if first
        end

        # Parse a data file's content by the extension carried on `path` (the
        # template-facing argument). Returns nil for unsupported types.
        #
        # The extension→format mapping stays a suffix match rather than
        # `File.extname` (which reads a bare ".json" as a dotfile, not an
        # extension), and the content is handed over WITHOUT a BOM strip —
        # both are long-standing `load_data()` behavior. Only the
        # format→Crinja parsing itself is shared with `data/` files and
        # `[[data.remote]]`.
        private def parse_data_content(path : String, content : String) : Crinja::Value?
          format = if path.ends_with?(".json")
                     "json"
                   elsif path.ends_with?(".toml")
                     "toml"
                   elsif path.ends_with?(".yaml") || path.ends_with?(".yml")
                     "yaml"
                   elsif path.ends_with?(".csv")
                     "csv"
                   end
          unless format
            Logger.debug "load_data('#{path}'): unsupported file type '#{File.extname(path)}' (supported: .json, .toml, .yaml, .yml, .csv)"
            return
          end
          Utils::CrinjaUtils.parse_data_string(content, format)
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
            TemplateEngine.record_render_read(ENV_READ_PREFIX + var_name)

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
      end

      # Process-lifetime engine shared by builds (see Initialize#setup_crinja_env)
      module Template
        @@engine : TemplateEngine?

        # Get or create the template engine
        def self.engine : TemplateEngine
          @@engine ||= TemplateEngine.new
        end
      end
    end
  end
end
