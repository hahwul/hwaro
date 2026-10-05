# Config section — [search].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    class SearchConfig
      # `shards` partitions the index into `search/<id>.json` files plus a
      # `search/index.json` manifest so clients lazy-load only what they
      # need. `single_file` keeps the classic `search.json` alongside the
      # shards; `content_max_length` (> 0) truncates each entry's `content`
      # at a word boundary.
      VALID_SHARDS = %w[none section language section-language]

      # Facet names valid on every site; any taxonomy name is valid too.
      # `tags` always is: front matter `tags` is parsed without a
      # `[[taxonomies]]` entry.
      BUILTIN_FACETS = %w[section lang tags]
      # Record keys a taxonomy facet may not overwrite.
      RESERVED_FACETS = %w[url title content description heading version]

      property enabled : Bool
      property format : String
      property fields : Array(String)
      property filename : String
      property exclude : Array(String)
      property tokenize_cjk : Bool
      property shards : String
      property single_file : Bool
      property content_max_length : Int32
      # `split_by_heading` adds one record per h2/h3 section (`url#id`);
      # `facets` adds filterable fields to every record; `ui` publishes the
      # built-in client under `assets/hwaro-search/` (`search_tags`).
      property split_by_heading : Bool
      property facets : Array(String)
      property ui : Bool

      def initialize
        @enabled = false
        @format = "fuse_json"
        @fields = ["title", "content"]
        @filename = "search.json"
        @exclude = [] of String
        @tokenize_cjk = false
        @shards = "none"
        @single_file = true
        @content_max_length = 0
        @split_by_heading = false
        @facets = [] of String
        @ui = false
      end

      # The built-in UI ships only alongside an index it can fetch.
      def ui_enabled? : Bool
        @enabled && @ui
      end

      def sharded? : Bool
        @shards != "none"
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_search(config : Config)
        return unless s = config.raw["search"]?.try(&.as_h?)

        config.search.enabled = bool_value(s["enabled"]?, config.search.enabled)
        config.search.format = s["format"]?.try(&.as_s?) || config.search.format
        config.search.filename = s["filename"]?.try(&.as_s?) || config.search.filename
        validate_output_filename!("search", "filename", config.search.filename, "search.json", allow_empty: false)
        if fields = string_list?(s["fields"]?, "[search] fields")
          config.search.fields = fields
        end
        if exclude = string_list?(s["exclude"]?, "[search] exclude")
          config.search.exclude = exclude
        end
        config.search.tokenize_cjk = bool_value(s["tokenize_cjk"]?, config.search.tokenize_cjk)
        if shards_any = s["shards"]?
          shards = shards_any.as_s?
          if shards && SearchConfig::VALID_SHARDS.includes?(shards)
            config.search.shards = shards
          else
            Logger.warn "Unknown search.shards #{shards_any.raw.inspect} (expected one of: #{SearchConfig::VALID_SHARDS.join(", ")}); using \"none\""
          end
        end
        config.search.single_file = bool_value(s["single_file"]?, config.search.single_file)
        max_len = int_value(s["content_max_length"]?, config.search.content_max_length)
        if max_len < 0
          Logger.warn "Ignoring negative search.content_max_length #{max_len}; using 0 (no truncation)"
          max_len = 0
        end
        config.search.content_max_length = max_len
        config.search.split_by_heading = bool_value(s["split_by_heading"]?, config.search.split_by_heading)
        if facets = string_list?(s["facets"]?, "[search] facets")
          config.search.facets = facets.uniq
        end
        config.search.ui = bool_value(s["ui"]?, config.search.ui)
        if config.search.ui && config.search.format.downcase.ends_with?("_javascript")
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "[search] ui = true needs a JSON index, but format is '#{config.search.format}'. The built-in UI fetches the index on first open; a *_javascript index is a `var searchData = ...` script it cannot load.",
            hint: "Set [search] format = \"fuse_json\" or \"elasticlunr_json\", or drop ui = true.",
          )
        end
        Logger.warn "[search] ui = true has no effect while [search] enabled = false" if config.search.ui && !config.search.enabled
      end

      # Facets name taxonomies, so they are checked after `load_taxonomies`.
      # An unknown name is dropped with a warning, never an error.
      private def self.validate_search_facets(config : Config)
        return if config.search.facets.empty?
        valid = (SearchConfig::BUILTIN_FACETS + config.taxonomies.map(&.name)).uniq - SearchConfig::RESERVED_FACETS
        unknown = config.search.facets.reject { |f| valid.includes?(f) }
        return if unknown.empty?
        Logger.warn "Ignoring unknown [search] facets #{unknown.join(", ")} (valid: #{valid.join(", ")})"
        config.search.facets = config.search.facets - unknown
      end
    end
  end
end
