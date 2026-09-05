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

      property enabled : Bool
      property format : String
      property fields : Array(String)
      property filename : String
      property exclude : Array(String)
      property tokenize_cjk : Bool
      property shards : String
      property single_file : Bool
      property content_max_length : Int32

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
        if fields = s["fields"]?.try(&.as_a?)
          config.search.fields = fields.compact_map(&.as_s?)
        end
        if exclude_arr = s["exclude"]?.try(&.as_a?)
          config.search.exclude = exclude_arr.compact_map(&.as_s?)
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
      end
    end
  end
end
