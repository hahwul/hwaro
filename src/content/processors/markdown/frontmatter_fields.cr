# Markdown processor — date parsing, menu registrations and taxonomy terms from front matter.
#
# Reopens `Processors::Markdown`; the part require order and the processor
# registration live in ../markdown.cr. Parts only reopen the class: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      class Markdown < Base
        # Parse a TOML value that may be a native Time or a String
        private def parse_toml_time(val : TOML::Any?, key : String = "date", file_path : String = "") : Time?
          return unless val
          raw = val.raw
          if raw.is_a?(Time)
            raw
          else
            parse_time(val.as_s?, key, file_path)
          end
        end

        # Parse a YAML value that may be a native Time or a String. An UNQUOTED
        # YAML date (`date: 2024-03-15`) resolves to a native Time node, so the
        # old `.as_s?` returned nil and silently dropped the date — breaking
        # sorting/feeds/sitemap. Mirrors parse_toml_time and content_lister.cr.
        private def parse_yaml_time(val : YAML::Any?, key : String = "date", file_path : String = "") : Time?
          return unless val
          if t = val.as_time?
            t
          else
            parse_time(val.as_s?, key, file_path)
          end
        end

        # Unparseable and out-of-range dates return nil so the rest of the
        # front matter survives instead of the exception unwinding the parse —
        # but not silently: `date = "2026-13-45"` or `date = "Sept 1, 2026"`
        # used to make the page undated (sorted last, missing from date-based
        # listings) with no feedback at all, while `tool validate` flagged it.
        # Library callers (no file_path) keep the quiet nil.
        private def parse_time(time_str : String?, key : String = "date", file_path : String = "") : Time?
          parsed = Utils::DateUtils.parse_content_date(time_str)
          if parsed.nil? && time_str && !time_str.strip.empty? && !file_path.empty?
            Logger.warn "#{file_path}: `#{key}` #{time_str.inspect} is not a recognised date (use YYYY-MM-DD, YYYY-MM-DD HH:MM:SS or RFC 3339) — treating it as unset."
          end
          parsed
        end

        # Extract named-menu front-matter registrations. Accepts the plural
        # `menus` key (wins if both are present) or the singular alias
        # `menu`, in three shapes:
        #   - bare string:    `menus = "main"`
        #   - array of names: `menus = ["main", "footer"]`
        #   - table form:     `[menus.main]` with name/weight/parent/identifier
        # All fields in the table form are optional — the menu builder falls
        # back to the page's own title/weight/no-parent/name-as-identifier.
        private def extract_menus(fm : TOML::Table | YAML::Any | JSON::Any) : Hash(String, Models::MenuRegistration)
          registrations = {} of String => Models::MenuRegistration
          value = fm["menus"]? || fm["menu"]?
          return registrations unless value

          if name = value.as_s?
            registrations[name] = Models::MenuRegistration.new
            return registrations
          end

          if arr = value.as_a?
            arr.compact_map(&.as_s?).each do |menu_name|
              registrations[menu_name] = Models::MenuRegistration.new
            end
            return registrations
          end

          # Table form. TOML/JSON hashes keep String keys; YAML hashes are
          # keyed by YAML::Any (mirrors `extract_taxonomies` below).
          case value
          when TOML::Any, JSON::Any
            value.as_h?.try &.each do |menu_name, entry|
              registrations[menu_name] = menu_registration_from(entry)
            end
          when YAML::Any
            value.as_h?.try &.each do |menu_name_any, entry|
              next unless menu_name = menu_name_any.as_s?
              registrations[menu_name] = menu_registration_from(entry)
            end
          end

          registrations
        end

        # Builds a single `MenuRegistration` from one table-form `[menus.<name>]`
        # entry. Guards with `as_h?` first because `TOML::Any#[]?` /
        # `YAML::Any#[]?` / `JSON::Any#[]?` raise (rather than returning nil)
        # when the underlying value isn't a Hash — so a malformed
        # `menus.main = "oops"` degrades to all-defaults instead of crashing
        # the page parse.
        private def menu_registration_from(entry : TOML::Any | YAML::Any | JSON::Any) : Models::MenuRegistration
          return Models::MenuRegistration.new unless entry.as_h?

          Models::MenuRegistration.new(
            name: entry["name"]?.try(&.as_s?),
            # Same clamped 64-bit read as `fm_int?`: a menu weight above
            # Int32::MAX must not raise OverflowError out of the parse.
            weight: entry["weight"]?.try { |val| fm_int_value?(val) },
            parent: entry["parent"]?.try(&.as_s?),
            identifier: entry["identifier"]?.try(&.as_s?),
          )
        end

        # Array-typed front matter keys that are NOT taxonomies.
        # These are excluded from automatic taxonomy extraction.
        NON_TAXONOMY_ARRAY_KEYS = Set{"tags", "aliases", "authors"}

        private def extract_taxonomies(front_matter : TOML::Table | YAML::Any | JSON::Any, keys : Array(String)) : Hash(String, Array(String))
          taxonomies = {} of String => Array(String)

          # Iterate all keys: TOML::Table yields {String, TOML::Any},
          # YAML::Any#as_h yields {YAML::Any, YAML::Any}. Unify via keys list.
          # Terms are stripped and blank-dropped for the same reasons as
          # `fm_string_array`: whitespace-padded terms must not become
          # distinct taxonomy terms or leak padded strings into term-page
          # titles and feeds, and a term that strips to "" never gets a
          # written page, so exposing it renders a link to a 404.
          keys.each do |key|
            next if NON_TAXONOMY_ARRAY_KEYS.includes?(key)
            if arr = front_matter[key]?.try(&.as_a?)
              values = arr.compact_map(&.as_s?).map(&.strip).reject(&.empty?)
              taxonomies[key] = values
            end
          end

          # Zola compat: terms may also live under a `[taxonomies]` table
          # (`[taxonomies]` / `taxonomies:` followed by `tech = ["crystal"]`).
          # These used to fall through to `extra` silently. Nested entries
          # overwrite a same-named top-level array key here, but the call
          # sites re-assert explicit top-level `tags` afterwards, so for
          # `tags` the dedicated key still wins overall.
          if table = front_matter["taxonomies"]?
            case table
            when TOML::Any, JSON::Any
              table.as_h?.try &.each do |k, v|
                if arr = v.as_a?
                  taxonomies[k] = arr.compact_map(&.as_s?).map(&.strip).reject(&.empty?)
                end
              end
            when YAML::Any
              table.as_h?.try &.each do |k, v|
                next unless key_str = k.as_s?
                if arr = v.as_a?
                  taxonomies[key_str] = arr.compact_map(&.as_s?).map(&.strip).reject(&.empty?)
                end
              end
            end
          end

          taxonomies
        end
      end
    end
  end
end
