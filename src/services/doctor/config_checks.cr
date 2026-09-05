# Doctor — config.toml diagnostics.
#
# Split out of doctor.cr, which keeps the require order, the Doctor ivars
# and `run`. Parts only define or reopen types: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Doctor
      # The config.toml group: load the file (a missing or unparseable
      # config blocks every other config check — see CHECK_GROUPS), then run
      # one small check per CheckSpec. Push order = report order, so a new
      # diagnostic goes in the position its CheckSpec has in the registry.
      private def check_config(issues : Array(Issue)) : Models::Config?
        unless File.exists?(@config_path)
          # Missing config.toml blocks every build path (`Config.load`
          # raises `HWARO_E_CONFIG`), so surface it as an error — not an
          # advisory — so CI can gate on `doctor`'s exit code.
          issues << Issue.new(id: "config-not-found", level: :error, category: "config", file: @config_path, message: "Config file not found")
          return
        end

        begin
          config = Models::Config.load(@config_path)
        rescue ex
          issues << Issue.new(id: "config-parse-error", level: :error, category: "config", file: @config_path, message: "Failed to parse config: #{ex.message}")
          return
        end

        check_base_url(issues, config)
        check_title(issues, config)
        check_sitemap_changefreq(issues, config)
        check_sitemap_priority(issues, config)
        check_taxonomy_duplicates(issues, config)
        check_search_format(issues, config)
        check_language_duplicates(issues, config)
        check_default_language(issues, config)
        check_version_paths(issues, config)
        check_math_engine(issues, config)
        check_image_processing_widths(issues, config)
        check_pwa_enums(issues, config)
        check_deployment_target(issues, config)
        check_related_taxonomies(issues, config)
        check_menu_parents(issues, config)
        check_missing_config_sections(issues)

        config
      end

      private def check_base_url(issues : Array(Issue), config : Models::Config) : Nil
        # base_url check
        #
        # Scheme/host validity is enforced at `Models::Config.load` time via
        # `validate_base_url!`, so any base_url reaching this point is either
        # empty or a well-formed http(s) URL. We only cover the remaining
        # style advisories here.
        # `config.base_url` is normalized (trailing slash stripped) on load, so
        # inspect the RAW config value for the trailing-slash advisory — the
        # build is already correct, but `--fix` still tidies the file.
        raw_base_url = config.raw["base_url"]?.try(&.as_s?)
        if config.base_url.empty?
          issues << Issue.new(id: "base-url-missing", level: :warning, category: "config", file: @config_path, message: "base_url is not set")
        elsif raw_base_url && raw_base_url.ends_with?("/")
          issues << Issue.new(id: "base-url-trailing-slash", level: :warning, category: "config", file: @config_path,
            message: "base_url should not end with a trailing slash")
        end
      end

      private def check_title(issues : Array(Issue), config : Models::Config) : Nil
        # title check. An ABSENT `title` reaches here as the internal
        # "Hwaro Site" fallback, so reporting it as a placeholder value
        # sent the user grepping for a string their config doesn't
        # contain. Say which of the two it is.
        if config.raw["title"]?.try(&.as_s?).nil?
          issues << Issue.new(id: "title-default", level: :warning, category: "config", file: @config_path,
            message: "title is not set (the site falls back to \"#{config.title}\")")
        elsif Doctor.default_titles.includes?(config.title)
          issues << Issue.new(id: "title-default", level: :warning, category: "config", file: @config_path,
            message: "title is still the placeholder value \"#{config.title}\"")
        end
      end

      private def check_sitemap_changefreq(issues : Array(Issue), config : Models::Config) : Nil
        # sitemap changefreq validity
        unless VALID_CHANGEFREQS.includes?(config.sitemap.changefreq)
          issues << Issue.new(id: "sitemap-changefreq-invalid", level: :warning, category: "config", file: @config_path,
            message: "sitemap.changefreq \"#{config.sitemap.changefreq}\" is not valid (expected: #{VALID_CHANGEFREQS.join(", ")})")
        end
      end

      private def check_sitemap_priority(issues : Array(Issue), config : Models::Config) : Nil
        # sitemap priority range
        unless 0.0 <= config.sitemap.priority <= 1.0
          issues << Issue.new(id: "sitemap-priority-range", level: :warning, category: "config", file: @config_path,
            message: "sitemap.priority #{config.sitemap.priority} is out of range (expected: 0.0–1.0)")
        end
      end

      private def check_taxonomy_duplicates(issues : Array(Issue), config : Models::Config) : Nil
        # taxonomy name duplicates — read from the raw TOML: the loader now
        # drops a repeated name (first declaration wins), so the parsed
        # `config.taxonomies` can no longer show the duplicate.
        taxonomy_names = (config.raw["taxonomies"]?.try(&.as_a?) || [] of TOML::Any)
          .compact_map { |t| t.as_h?.try(&.["name"]?).try(&.as_s?) }
        duplicates = taxonomy_names.tally.select { |_, count| count > 1 }.keys
        duplicates.each do |name|
          issues << Issue.new(id: "taxonomy-duplicate", level: :warning, category: "config", file: @config_path,
            message: "Duplicate taxonomy name: \"#{name}\"")
        end
      end

      private def check_search_format(issues : Array(Issue), config : Models::Config) : Nil
        # search format validity
        if config.search.enabled && !VALID_SEARCH_FORMATS.includes?(config.search.format)
          issues << Issue.new(id: "search-format-invalid", level: :warning, category: "config", file: @config_path,
            message: "search.format \"#{config.search.format}\" is not supported (expected: #{VALID_SEARCH_FORMATS.join(", ")})")
        end
      end

      private def check_language_duplicates(issues : Array(Issue), config : Models::Config) : Nil
        # duplicate language codes
        lang_codes = config.languages.keys
        lang_duplicates = lang_codes.tally.select { |_, count| count > 1 }.keys
        lang_duplicates.each do |code|
          issues << Issue.new(id: "language-duplicate", level: :warning, category: "config", file: @config_path,
            message: "Duplicate language code: \"#{code}\"")
        end
      end

      private def check_default_language(issues : Array(Issue), config : Models::Config) : Nil
        # default_language must resolve to a `[languages.<code>]` table.
        # Without this check a typo silently falls through to untranslated
        # content with broken hreflang tags and a feed that omits the
        # default locale.
        if !config.default_language.empty? && !config.languages.empty? && !config.languages.has_key?(config.default_language)
          known = config.languages.keys.sort!.join(", ")
          issues << Issue.new(id: "default-language-undefined", level: :warning, category: "config", file: @config_path,
            message: "default_language \"#{config.default_language}\" has no matching [languages.#{config.default_language}] block (defined: #{known})")
        end
      end

      private def check_version_paths(issues : Array(Issue), config : Models::Config) : Nil
        # Every `[[versions.list]]` path must be a real content directory:
        # a typo'd path silently publishes an empty version (its switcher
        # entry links to a 404 root).
        config.versions.list.each do |version|
          dir = File.join(@content_dir, version.path)
          next if Dir.exists?(dir)
          issues << Issue.new(id: "version-path-missing", level: :warning, category: "config", file: @config_path,
            message: "version \"#{version.name}\" points at content path \"#{version.path}\" which does not exist (#{dir})")
        end
      end

      private def check_math_engine(issues : Array(Issue), config : Models::Config) : Nil
        # markdown.math_engine only renders when set to a value the
        # build pipeline actually loads; other strings silently produce
        # no math. Skip when math is off — the field is a no-op there.
        if config.markdown.math && !VALID_MATH_ENGINES.includes?(config.markdown.math_engine)
          issues << Issue.new(id: "markdown-math-engine-invalid", level: :warning, category: "config", file: @config_path,
            message: "markdown.math_engine \"#{config.markdown.math_engine}\" is not supported (expected: #{VALID_MATH_ENGINES.join(", ")})")
        end
      end

      private def check_image_processing_widths(issues : Array(Issue), config : Models::Config) : Nil
        # An enabled [image_processing] with no widths is a silent no-op:
        # the image hook returns early on an empty widths array and the
        # renderer generates no srcset, so the user turns the feature on
        # and nothing visibly happens. Same "enabled but silently does
        # nothing" class as the math_engine and pwa checks around it.
        if config.image_processing.enabled && config.image_processing.widths.empty?
          issues << Issue.new(id: "image-processing-widths-empty", level: :warning, category: "config", file: @config_path,
            message: "image_processing is enabled but widths is empty — no resized variants will be generated (set e.g. widths = [320, 640, 1024])")
        end
      end

      private def check_pwa_enums(issues : Array(Issue), config : Models::Config) : Nil
        # PWA cache_strategy is enforced at runtime via VALID_STRATEGIES.
        # `Models::Config.load` silently coerces an unknown value back
        # to "cache-first" (with a `Logger.warn` the user often misses
        # during build), so we read the user-typed value from the raw
        # TOML tree before that coercion kicks in.
        raw_pwa = config.raw["pwa"]?.try(&.as_h?)
        if raw_pwa && (raw_strategy = raw_pwa["cache_strategy"]?.try(&.as_s?))
          unless Models::PwaConfig::VALID_STRATEGIES.includes?(raw_strategy)
            issues << Issue.new(id: "pwa-cache-strategy-invalid", level: :warning, category: "config", file: @config_path,
              message: "pwa.cache_strategy \"#{raw_strategy}\" is not supported (expected: #{Models::PwaConfig::VALID_STRATEGIES.join(", ")})")
          end
        end
        # Same shape for `display`: `Config.load` coerces an unknown value
        # back to "standalone" with a build-time warning, so read the raw
        # TOML value here too. Before this check a typo (`display = "weird"`)
        # was invisible to doctor while browsers silently fell back.
        if raw_pwa && (raw_display = raw_pwa["display"]?.try(&.as_s?))
          unless Models::PwaConfig::VALID_DISPLAYS.includes?(raw_display)
            issues << Issue.new(id: "pwa-display-invalid", level: :warning, category: "config", file: @config_path,
              message: "pwa.display \"#{raw_display}\" is not supported (expected: #{Models::PwaConfig::VALID_DISPLAYS.join(", ")})")
          end
        end
      end

      private def check_deployment_target(issues : Array(Issue), config : Models::Config) : Nil
        # `[deployment].target` selects which `[[deployment.targets]]`
        # block `hwaro deploy` uses. Pointing at an undefined name
        # makes `deploy` fail at runtime with a "target not found"
        # error — catching it here surfaces the typo before the
        # operator runs the actual deploy.
        if (selected = config.deployment.target) && !selected.empty?
          unless config.deployment.targets.any? { |t| t.name == selected }
            known = config.deployment.targets.map(&.name).reject(&.empty?).sort!.join(", ")
            known_hint = known.empty? ? "no [[deployment.targets]] defined" : "defined: #{known}"
            issues << Issue.new(id: "deployment-target-undefined", level: :warning, category: "config", file: @config_path,
              message: "deployment.target \"#{selected}\" has no matching [[deployment.targets]] block (#{known_hint})")
          end
        end
      end

      private def check_related_taxonomies(issues : Array(Issue), config : Models::Config) : Nil
        # `[related].taxonomies` references taxonomy names from
        # `[[taxonomies]]`. A typo silently produces zero related
        # posts on every page without any user-visible signal — the
        # feature just looks broken.
        if config.related.enabled
          known_taxonomies = config.taxonomies.map(&.name)
          config.related.taxonomies.each do |name|
            next if known_taxonomies.includes?(name)
            known_hint = known_taxonomies.empty? ? "no [[taxonomies]] defined" : "defined: #{known_taxonomies.sort!.join(", ")}"
            issues << Issue.new(id: "related-taxonomy-undefined", level: :warning, category: "config", file: @config_path,
              message: "[related] taxonomies references \"#{name}\" but no [[taxonomies]] block defines it (#{known_hint})")
          end
        end
      end

      private def check_menu_parents(issues : Array(Issue), config : Models::Config) : Nil
        # `[[menus.<name>]]` entries may set `parent` to another entry's
        # `identifier` within the SAME menu (global or per-language). A typo
        # silently falls through to Content::Menus's "promoted to root"
        # fallback at build time with only a build-log warning — surface it
        # here so it's caught before build. Per-language menu sets fully
        # replace the global one (no per-language override ⇒ `menus` is
        # `nil`, inheriting the global set already checked), so each is
        # validated independently against its OWN identifiers.
        check_menu_parent_undefined(issues, "", config.menus)
        config.languages.keys.sort!.each do |code|
          lang_menus = config.languages[code].menus
          check_menu_parent_undefined(issues, code, lang_menus) if lang_menus
        end
      end

      private def check_menu_parent_undefined(issues : Array(Issue), lang_code : String, menus : Hash(String, Array(Models::MenuItemConfig)))
        menus.each do |menu_name, items|
          identifiers = items.map(&.identifier).to_set
          scope = lang_code.empty? ? "[[menus.#{menu_name}]]" : "[[languages.#{lang_code}.menus.#{menu_name}]]"
          items.each do |item|
            parent = item.parent
            next if parent.nil? || parent.empty?
            next if identifiers.includes?(parent)
            issues << Issue.new(id: "menu-parent-undefined", level: :warning, category: "config", file: @config_path,
              message: "#{scope} entry \"#{item.name}\" has parent \"#{parent}\" but no entry in that menu declares identifier \"#{parent}\"")
          end
        end
      end

      private def check_missing_config_sections(issues : Array(Issue))
        missing = missing_config_sections
        return if missing.empty?

        missing.each do |key|
          # Niche/advanced sections are intentionally skipped by `--fix` in its
          # minimal mode (see `fix_config`), so flagging them here would tell
          # users to run a command that won't add them. Stay silent for those —
          # users opt in by manually configuring the section.
          next if OPTIONAL_SECTIONS.includes?(key)
          desc = KNOWN_CONFIG_SECTIONS[key]? || KNOWN_SUB_SECTIONS.find { |k, _| "#{k[0]}.#{k[1]}" == key }.try(&.last) || key
          issues << Issue.new(id: "missing-config-#{key}", level: :info, category: "config_missing", file: @config_path,
            message: "Optional section [#{key}] not present (#{desc}). Add it manually if needed, or use 'hwaro doctor --full' for recommendations.")
        end
      end
    end
  end
end
