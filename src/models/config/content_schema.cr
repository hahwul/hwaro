# Config section — [[content.schema]].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # A front-matter value as the schema sees it: what `page.extra` holds,
    # plus the native TOML/YAML datetime a `date` field may carry.
    alias SchemaValue = ExtraValue | Time

    # One `[content.schema.fields.<name>]` entry. `name` is either a
    # top-level key (a known front-matter field, or an unknown key, which the
    # parser stores in `extra`) or `extra.<key>`.
    class ContentSchemaField
      TYPES = %w[string int float bool date array table]
      KEYS  = %w[type required enum default min max]

      # Known front-matter fields a `default` may fill: the ones read after
      # parsing (cascade's set plus a few listing fields). URL-, date- and
      # publication-window fields are resolved during parsing, so a default
      # on them could not take effect. `draft` is left out on purpose: the
      # tools' publish state (ContentLister) reads front matter and
      # [cascade] only, and a default it cannot see would split the page set.
      DEFAULTABLE_KNOWN = %w[description image template render toc insert_anchor_links
        in_sitemap in_search_index weight series series_weight tags authors updated]

      # The type each known front-matter field has to the parser. A schema
      # may only declare that type for it (`menus`/`menu` take several shapes
      # and are not listed).
      KNOWN_TYPES = {
        "title" => "string", "description" => "string", "image" => "string", "template" => "string",
        "slug" => "string", "path" => "string", "sort_by" => "string", "page_template" => "string",
        "paginate_path" => "string", "redirect_to" => "string", "series" => "string",
        "draft" => "bool", "in_sitemap" => "bool", "toc" => "bool", "render" => "bool",
        "transparent" => "bool", "generate_feeds" => "bool", "pagination_enabled" => "bool",
        "reverse" => "bool", "in_search_index" => "bool", "insert_anchor_links" => "bool",
        "paginate" => "int", "paginate_by" => "int", "weight" => "int", "series_weight" => "int",
        "date" => "date", "updated" => "date", "expires" => "date",
        "aliases" => "array", "tags" => "array", "authors" => "array", "categories" => "array",
        "taxonomies" => "table", "cascade" => "table",
      }

      getter name : String
      getter type : String
      getter required : Bool
      getter enum_values : Array(SchemaValue)?
      getter default : SchemaValue?
      getter min : Float64?
      getter max : Float64?

      def initialize(@name, @type, @required = false, @enum_values = nil, @default = nil, @min = nil, @max = nil)
      end

      # `extra.rating` → "rating"; a top-level name → nil.
      def extra_key : String?
        @name.starts_with?("extra.") ? @name.lchop("extra.") : nil
      end

      # The first problem with `value` (type, enum, bounds), or nil.
      def problem(value : SchemaValue) : String?
        actual = ContentSchemaField.type_name(value)
        unless type_accepts?(value)
          return "expected #{@type}, got #{actual}#{" #{ContentSchemaField.show(value)}" if actual == "string"}"
        end
        if (allowed = @enum_values) && !allowed.includes?(value)
          return "#{ContentSchemaField.show(value)} is not one of #{allowed.map(&.inspect).join(", ")}"
        end
        return "NaN is outside the bounds" if value.is_a?(Float64) && value.nan? && (@min || @max)
        measure, what = case value
                        when Int64, Float64 then {value.to_f, value.inspect}
                        when String         then {value.size.to_f, "length #{value.size}"}
                        when Array          then {value.size.to_f, "length #{value.size}"}
                        else                     return
                        end
        if (lo = @min) && measure < lo
          return "#{what} is less than the minimum #{ContentSchemaField.number(lo)}"
        end
        if (hi = @max) && measure > hi
          "#{what} is greater than the maximum #{ContentSchemaField.number(hi)}"
        end
      end

      # `int` and `float` are distinct on purpose: `rating = 4.0` is not an
      # int and `price = 4` is not a float. `date` accepts what the `date`
      # front-matter field accepts: a native datetime or a string the
      # content date parser reads.
      private def type_accepts?(value : SchemaValue) : Bool
        case @type
        when "date"   then value.is_a?(Time) || (value.is_a?(String) && !Utils::DateUtils.parse_content_date(value).nil?)
        when "string" then value.is_a?(String)
        else               ContentSchemaField.type_name(value) == @type
        end
      end

      def self.type_name(value : SchemaValue) : String
        case value
        in String  then "string"
        in Int64   then "int"
        in Float64 then "float"
        in Bool    then "bool"
        in Time    then "date"
        in Array   then "array"
        in Hash    then "table"
        end
      end

      # `value.inspect`, cut to about 80 characters for messages.
      def self.show(value : SchemaValue) : String
        text = value.inspect
        text.size > 80 ? "#{text[0, 79]}…" : text
      end

      def self.number(value : Float64) : String
        value == value.round ? value.to_i64.to_s : value.to_s
      end
    end

    # One `[[content.schema]]` entry: the fields every regular page in the
    # matching sections must satisfy. See Content::FrontMatterSchema.
    class ContentSchemaConfig
      KEYS = %w[sections strict fields]

      getter sections : Array(String)
      getter strict : Bool
      getter fields : Array(ContentSchemaField)

      def initialize(@sections, @strict, @fields)
      end

      # `section` is `Page#section` ("" for root pages). A pattern ending in
      # `/**` also matches the directory itself, so "docs/**" covers
      # `docs/intro.md` as well as `docs/guide/intro.md`.
      def matches?(section : String) : Bool
        @sections.any? do |pattern|
          Utils::PathUtils.glob_match?(pattern, section) ||
            (pattern.ends_with?("/**") && section == pattern[0, pattern.size - 3])
        end
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      # `[[content.schema]]` — front-matter schemas per section (see
      # ContentSchemaConfig). Every shape error is a hard config error: a
      # mistyped schema would otherwise validate nothing, silently.
      private def self.load_content_schema(config : Config)
        return unless content_section = config.raw["content"]?.try(&.as_h?)
        return unless schema_any = content_section["schema"]?

        list = schema_any.as_a? ||
               raise schema_config_error("'content.schema' must be an array of tables — declare each schema with [[content.schema]] (double brackets).")

        config.content_schema = list.map_with_index do |entry_any, index|
          where = "[[content.schema]] entry #{index + 1}"
          entry = entry_any.as_h? || raise schema_config_error("#{where} must be a table.")
          reject_unknown_schema_keys!(entry.keys, ContentSchemaConfig::KEYS, where)

          sections_any = entry["sections"]? ||
                         raise schema_config_error("#{where} is missing 'sections' (section path globs such as [\"posts\", \"docs/**\"]; \"\" is the root).")
          section_list = sections_any.as_a? || [sections_any]
          sections = section_list.map do |s|
            s.as_s?.try(&.strip.strip('/')) || raise schema_config_error("#{where}: 'sections' must be a string or an array of strings.")
          end
          strict = schema_bool(entry["strict"]?, "strict", where)

          fields = [] of ContentSchemaField
          if fields_any = entry["fields"]?
            fields_table = fields_any.as_h? || raise schema_config_error("#{where}: 'fields' must be a table of [content.schema.fields.<name>] tables.")
            fields_table.each do |name, field_any|
              fields << load_schema_field(name, field_any, "#{where} field \"#{name}\"")
            end
          end

          ContentSchemaConfig.new(sections, strict, fields)
        end
      end

      private def self.load_schema_field(name : String, field_any : TOML::Any, where : String) : ContentSchemaField
        if name == "extra"
          raise schema_config_error("#{where}: name extra fields one by one, quoting the dotted name: [content.schema.fields.\"extra.rating\"].")
        end
        extra_key = name.starts_with?("extra.") ? name.lchop("extra.") : name
        if extra_key.empty? || extra_key.includes?('.')
          raise schema_config_error("#{where}: a field name is a front-matter key or extra.<key>; nothing nests deeper.")
        end

        field = field_any.as_h? || raise schema_config_error("#{where} must be a table with at least a 'type'.")
        reject_unknown_schema_keys!(field.keys, ContentSchemaField::KEYS, where)

        type = field["type"]?.try(&.as_s?) ||
               raise schema_config_error("#{where} is missing 'type' (one of #{ContentSchemaField::TYPES.join(", ")}).")
        unless ContentSchemaField::TYPES.includes?(type)
          hint = Utils::CommandSuggester.suggest(type, ContentSchemaField::TYPES).try { |s| " Did you mean '#{s}'?" }
          raise schema_config_error("#{where}: unknown type '#{type}' — expected one of #{ContentSchemaField::TYPES.join(", ")}.#{hint}")
        end

        required = schema_bool(field["required"]?, "required", where)

        enum_values = nil
        if enum_any = field["enum"]?
          unless type.in?("string", "int", "float")
            raise schema_config_error("#{where}: 'enum' applies to string, int and float fields, not #{type}.")
          end
          values = enum_any.as_a? || raise schema_config_error("#{where}: 'enum' must be an array.")
          enum_values = values.map do |value_any|
            value = schema_value(value_any)
            actual = ContentSchemaField.type_name(value)
            raise schema_config_error("#{where}: enum value #{value.inspect} is a #{actual}, not a #{type}.") unless actual == type
            value
          end
        end

        min = schema_bound(field["min"]?, "min", type, where)
        max = schema_bound(field["max"]?, "max", type, where)
        if (lo = min) && (hi = max) && lo > hi
          raise schema_config_error("#{where}: min (#{ContentSchemaField.number(lo)}) is greater than max (#{ContentSchemaField.number(hi)}).")
        end

        known_type = name.starts_with?("extra.") ? nil : ContentSchemaField::KNOWN_TYPES[name]?
        if known_type && known_type != type
          raise schema_config_error("#{where}: '#{name}' is #{known_type == "int" || known_type == "array" ? "an" : "a"} #{known_type} front-matter field; declare type = \"#{known_type}\".")
        end

        built = ContentSchemaField.new(name, type, required, enum_values, nil, min, max)
        if default_any = field["default"]?
          if name == "draft"
            raise schema_config_error("#{where}: 'draft' cannot take a default — doctor and `tool list` decide what publishes from front matter and [cascade] alone. Set draft in the page or in a section's [cascade].")
          end
          if !name.starts_with?("extra.") && Content::Processors::Markdown::KNOWN_FRONT_MATTER_KEYS.includes?(name) &&
             !ContentSchemaField::DEFAULTABLE_KNOWN.includes?(name)
            raise schema_config_error("#{where}: '#{name}' is resolved while the page is parsed, so a default cannot apply. Defaults can fill extra keys and #{ContentSchemaField::DEFAULTABLE_KNOWN.join(", ")}.")
          end
          default = schema_value(default_any)
          if problem = built.problem(default)
            raise schema_config_error("#{where}: default #{default.inspect} does not satisfy the field: #{problem}.")
          end
          built = ContentSchemaField.new(name, type, required, enum_values, default, min, max)
        end
        built
      end

      private def self.schema_bound(raw : TOML::Any?, key : String, type : String, where : String) : Float64?
        return unless raw
        unless type.in?("int", "float", "string", "array")
          raise schema_config_error("#{where}: '#{key}' applies to int and float (value) and string and array (length) fields, not #{type}.")
        end
        bound = raw.as_f? || raw.as_i64?.try(&.to_f)
        raise schema_config_error("#{where}: '#{key}' must be a number.") if bound.nil? || bound.nan?
        bound
      end

      private def self.schema_bool(raw : TOML::Any?, key : String, where : String) : Bool
        return false unless raw
        value = raw.as_bool?
        raise schema_config_error("#{where}: '#{key}' must be true or false.") if value.nil?
        value
      end

      private def self.schema_value(raw : TOML::Any) : SchemaValue
        time = raw.raw
        time.is_a?(Time) ? time : Processor::Markdown.extra_value(raw)
      end

      private def self.reject_unknown_schema_keys!(keys : Array(String), known : Array(String), where : String)
        keys.each do |key|
          next if known.includes?(key)
          hint = Utils::CommandSuggester.suggest(key, known).try { |s| " Did you mean '#{s}'?" }
          raise schema_config_error("#{where}: unknown key '#{key}'.#{hint} Known keys: #{known.join(", ")}.")
        end
      end

      private def self.schema_config_error(message : String) : Hwaro::HwaroError
        Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: message,
          hint: "Each [[content.schema]] needs sections = [...] and [content.schema.fields.<name>] tables with type = string|int|float|bool|date|array|table; optional: required, enum, default, min, max.",
        )
      end
    end
  end
end
