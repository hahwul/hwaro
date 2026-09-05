# Config section — [languages], [menus] and [[taxonomies]].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    class TaxonomyConfig
      property name : String
      property feed : Bool
      property sitemap : Bool
      property paginate_by : Int32?
      # Ordering of pages within a term ("date", "title", "weight") —
      # section semantics: date is newest-first, title/weight ascend, and
      # `reverse` flips whichever order `sort_by` produced. Term FEEDS are
      # exempt: RSS consumers assume reverse-chronological, so they stay
      # date-desc regardless.
      property sort_by : String = "date"
      property reverse : Bool = false
      # Ordering of the terms list (taxonomy index page + `get_taxonomy`
      # items): "name" = alphabetical, "count" = page count descending
      # (name-ascending tiebreak).
      property terms_sort_by : String = "name"

      def initialize(@name : String)
        @feed = false
        @sitemap = true
        @paginate_by = nil
      end
    end

    # A single `[[menus.<name>]]` entry from config. `name` is the only
    # required field (entries missing it are skipped with a warning by the
    # loader); everything else defaults so `[[menus.main]]\nname = "Posts"`
    # is valid on its own.
    class MenuItemConfig
      property name : String
      property url : String
      property identifier : String
      property parent : String?
      property weight : Int32

      def initialize(@name : String, @url : String = "", identifier : String? = nil, @parent : String? = nil, @weight : Int32 = 0)
        @identifier = identifier || @name
      end
    end

    # Language configuration for multilingual sites
    class LanguageConfig
      property code : String
      property language_name : String
      property weight : Int32
      property generate_feed : Bool
      property build_search_index : Bool
      property taxonomies : Array(String)
      # `nil` means "no per-language override" → inherit the global
      # `[[menus.*]]` set wholesale (see `load_languages`).
      property menus : Hash(String, Array(MenuItemConfig))? = nil

      def initialize(@code : String)
        @language_name = code
        @weight = 1
        @generate_feed = true
        @build_search_index = true
        @taxonomies = ["tags", "categories"]
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      # Parses a `menus` TOML table (either the top-level `[[menus.*]]` set
      # or a per-language `[[languages.<code>.menus.*]]` override) into
      # `{menu_name => [MenuItemConfig]}`. Shared by `load_menus` and
      # `load_languages` so both surfaces accept identical entry shapes.
      private def self.parse_menu_tables(h : Hash(String, TOML::Any)) : Hash(String, Array(MenuItemConfig))
        result = {} of String => Array(MenuItemConfig)

        h.each do |menu_name, menu_value|
          entries = menu_value.as_a?
          next unless entries

          result[menu_name] = entries.compact_map do |entry_any|
            entry_hash = entry_any.as_h?
            unless entry_hash
              Logger.warn "Ignoring non-table entry in [[menus.#{menu_name}]]"
              next
            end

            name = entry_hash["name"]?.try(&.as_s?)
            unless name
              Logger.warn "Skipping [[menus.#{menu_name}]] entry missing required `name`"
              next
            end

            item = MenuItemConfig.new(name)
            item.url = entry_hash["url"]?.try(&.as_s?) || ""
            item.weight = int_value(entry_hash["weight"]?, 0)
            item.identifier = entry_hash["identifier"]?.try(&.as_s?) || name
            item.parent = entry_hash["parent"]?.try(&.as_s?)
            item
          end
        end

        result
      end

      private def self.load_menus(config : Config)
        return unless menus_section = config.raw["menus"]?.try(&.as_h?)

        config.menus = parse_menu_tables(menus_section)
      end

      private def self.load_taxonomies(config : Config)
        return unless taxonomies_section = config.raw["taxonomies"]?.try(&.as_a?)

        # A name declared twice used to yield two TaxonomyConfig entries, and
        # every consumer iterating `config.taxonomies` registered each page
        # under the name twice: term pages listed every post two times, the
        # term feed carried duplicate items, `paginate_by` split a doubled
        # list, and a lookup by name could land on either declaration (so
        # `terms_sort_by` set on the first one silently stopped applying).
        # `hwaro doctor` already flags the duplicate; the build has to refuse
        # it too. First declaration wins, like a table-array key.
        seen = Set(String).new
        config.taxonomies = taxonomies_section.compact_map do |taxonomy_any|
          taxonomy_hash = taxonomy_any.as_h?
          next unless taxonomy_hash

          name = taxonomy_hash["name"]?.try(&.as_s?)
          next unless name
          unless seen.add?(name)
            Logger.warn "Duplicate [[taxonomies]] name #{name.inspect} in config.toml — the first declaration wins; remove the later one."
            next
          end

          taxonomy = TaxonomyConfig.new(name)
          taxonomy.feed = bool_value(taxonomy_hash["feed"]?, taxonomy.feed)
          taxonomy.sitemap = bool_value(taxonomy_hash["sitemap"]?, taxonomy.sitemap)
          taxonomy.paginate_by = taxonomy_hash["paginate_by"]?.try { |v| int_or_nil(v) }
          if sort_by = taxonomy_hash["sort_by"]?.try(&.as_s?)
            if {"date", "title", "weight"}.includes?(sort_by)
              taxonomy.sort_by = sort_by
            else
              Logger.warn "Unknown taxonomy sort_by '#{sort_by}' for '#{name}' — expected \"date\", \"title\" or \"weight\". Using \"date\"."
            end
          end
          taxonomy.reverse = bool_value(taxonomy_hash["reverse"]?, taxonomy.reverse)
          if terms_sort_by = taxonomy_hash["terms_sort_by"]?.try(&.as_s?)
            if {"name", "count"}.includes?(terms_sort_by)
              taxonomy.terms_sort_by = terms_sort_by
            else
              Logger.warn "Unknown taxonomy terms_sort_by '#{terms_sort_by}' for '#{name}' — expected \"name\" or \"count\". Using \"name\"."
            end
          end
          taxonomy
        end
      end

      private def self.load_languages(config : Config)
        return unless s = config.raw["languages"]?.try(&.as_h?)

        # Collect into a local hash and assign through `languages=` at the
        # end: the setter invalidates the `multilingual?` memo, so the
        # invariant holds structurally instead of depending on nothing
        # having called `multilingual?` before this loader runs.
        languages = config.languages.dup

        s.each do |lang_code, lang_data|
          next unless lang_hash = lang_data.as_h?

          lang_config = LanguageConfig.new(lang_code)
          lang_config.language_name = lang_hash["language_name"]?.try(&.as_s?) || lang_code
          lang_config.weight = int_value(lang_hash["weight"]?, lang_config.weight)
          lang_config.generate_feed = bool_value(lang_hash["generate_feed"]?, lang_config.generate_feed)
          lang_config.build_search_index = bool_value(lang_hash["build_search_index"]?, lang_config.build_search_index)

          if taxonomies = lang_hash["taxonomies"]?.try(&.as_a?)
            lang_config.taxonomies = taxonomies.compact_map(&.as_s?)
          else
            # No per-language `taxonomies` key → inherit the global
            # `[[taxonomies]]` set rather than the hardcoded `["tags",
            # "categories"]` default. Otherwise a `[languages.<code>]` block
            # that omits the key silently restricts that language to two
            # taxonomies, dropping any third (e.g. `authors`) from its output —
            # for the default language that means a taxonomy generated before
            # this block existed would disappear at the root. `load_taxonomies`
            # runs before `load_languages`, so `config.taxonomies` is populated.
            lang_config.taxonomies = config.taxonomies.map(&.name)
          end

          if menus = lang_hash["menus"]?.try(&.as_h?)
            lang_config.menus = parse_menu_tables(menus)
          end
          # No per-language `menus` key → leave `lang_config.menus` as `nil`,
          # signalling "inherit the global `[[menus.*]]` set wholesale" to
          # `Content::Menus.build`.

          languages[lang_code] = lang_config
        end

        config.languages = languages
      end
    end
  end
end
