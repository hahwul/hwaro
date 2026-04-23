# Frontmatter Converter Service
#
# This service provides functionality to convert frontmatter between
# YAML, TOML, and JSON formats in content files.

require "json"
require "yaml"
require "toml"
require "../utils/frontmatter_scanner"
require "../utils/logger"

module Hwaro
  module Services
    # Frontmatter format types
    enum FrontmatterFormat
      YAML
      TOML
      JSON
      Unknown
    end

    # Result of a conversion operation
    struct ConversionResult
      include JSON::Serializable

      property success : Bool
      property message : String
      property converted_count : Int32
      property skipped_count : Int32
      property error_count : Int32

      def initialize(
        @success : Bool = true,
        @message : String = "",
        @converted_count : Int32 = 0,
        @skipped_count : Int32 = 0,
        @error_count : Int32 = 0,
      )
      end
    end

    # Frontmatter Converter converts between YAML and TOML formats
    class FrontmatterConverter
      YAML_DELIMITER = "---"
      TOML_DELIMITER = "+++"

      private enum ConversionStatus
        Converted
        Skipped
        Failed
        Error
      end

      # Content directory path
      @content_dir : String

      def initialize(@content_dir : String = "content")
      end

      # Convert all content files to YAML format
      def convert_to_yaml : ConversionResult
        convert_files(FrontmatterFormat::YAML)
      end

      # Convert all content files to TOML format
      def convert_to_toml : ConversionResult
        convert_files(FrontmatterFormat::TOML)
      end

      # Convert all content files to JSON format
      def convert_to_json : ConversionResult
        convert_files(FrontmatterFormat::JSON)
      end

      # Detect the frontmatter format of a file
      def detect_format(content : String) : FrontmatterFormat
        if content.starts_with?("#{TOML_DELIMITER}\n") || content.starts_with?("#{TOML_DELIMITER}\r\n")
          FrontmatterFormat::TOML
        elsif content.starts_with?("#{YAML_DELIMITER}\n") || content.starts_with?("#{YAML_DELIMITER}\r\n")
          FrontmatterFormat::YAML
        elsif content.starts_with?('{') && Hwaro::Utils::FrontmatterScanner.find_json_end(content)
          FrontmatterFormat::JSON
        else
          FrontmatterFormat::Unknown
        end
      end

      # Convert a single file's frontmatter
      def convert_file(file_path : String, target_format : FrontmatterFormat) : Bool
        status = convert_file_with_status(file_path, target_format, log_skipped: true)
        status == ConversionStatus::Converted
      end

      private def convert_file_with_status(file_path : String, target_format : FrontmatterFormat, log_skipped : Bool = true) : ConversionStatus
        content = File.read(file_path)
        current_format = detect_format(content)

        # Skip if already in target format or unknown format
        if current_format == target_format
          Logger.info "  Skipped (already #{target_format}): #{file_path}" if log_skipped
          return ConversionStatus::Skipped
        end

        if current_format == FrontmatterFormat::Unknown
          Logger.warn "  Skipped (no frontmatter): #{file_path}" if log_skipped
          return ConversionStatus::Skipped
        end

        converted_content = convert_content(content, current_format, target_format)

        if converted_content
          File.write(file_path, converted_content)
          Logger.success "  Converted: #{file_path}"
          ConversionStatus::Converted
        else
          Logger.error "  Failed to convert: #{file_path}"
          ConversionStatus::Failed
        end
      rescue ex
        Logger.error "  Error converting #{file_path}: #{ex.message}"
        ConversionStatus::Error
      end

      private def convert_files(target_format : FrontmatterFormat) : ConversionResult
        unless Dir.exists?(@content_dir)
          return ConversionResult.new(
            success: false,
            message: "Content directory '#{@content_dir}' not found"
          )
        end

        converted = 0
        skipped = 0
        errors = 0

        format_name = format_label(target_format)
        Logger.info "Converting frontmatter to #{format_name} format..."
        Logger.info ""

        find_content_files.each do |file_path|
          status = convert_file_with_status(file_path, target_format, log_skipped: false)

          case status
          when ConversionStatus::Converted
            converted += 1
          when ConversionStatus::Skipped
            skipped += 1
          when ConversionStatus::Failed, ConversionStatus::Error
            errors += 1
          end
        end

        Logger.info ""
        Logger.info "Conversion complete:"
        Logger.info "  Converted: #{converted}"
        Logger.info "  Skipped: #{skipped}"
        Logger.info "  Errors: #{errors}" if errors > 0

        ConversionResult.new(
          success: errors == 0,
          message: "Converted #{converted} files to #{format_name}",
          converted_count: converted,
          skipped_count: skipped,
          error_count: errors
        )
      end

      private def find_content_files : Array(String)
        files = [] of String

        Dir.glob(File.join(@content_dir, "**", "*.md")) do |file|
          files << file
        end

        Dir.glob(File.join(@content_dir, "**", "*.markdown")) do |file|
          files << file
        end

        files.sort
      end

      private def convert_content(content : String, from : FrontmatterFormat, to : FrontmatterFormat) : String?
        case {from, to}
        when {FrontmatterFormat::YAML, FrontmatterFormat::TOML}
          yaml_to_toml(content)
        when {FrontmatterFormat::TOML, FrontmatterFormat::YAML}
          toml_to_yaml(content)
        when {FrontmatterFormat::YAML, FrontmatterFormat::JSON}
          yaml_to_json(content)
        when {FrontmatterFormat::JSON, FrontmatterFormat::YAML}
          json_to_yaml(content)
        when {FrontmatterFormat::TOML, FrontmatterFormat::JSON}
          toml_to_json(content)
        when {FrontmatterFormat::JSON, FrontmatterFormat::TOML}
          json_to_toml(content)
        end
      end

      private def format_label(fmt : FrontmatterFormat) : String
        case fmt
        when FrontmatterFormat::YAML then "YAML"
        when FrontmatterFormat::TOML then "TOML"
        when FrontmatterFormat::JSON then "JSON"
        else                              "Unknown"
        end
      end

      # Split JSON-frontmatter content into (json_string, body). Returns nil if
      # the file does not start with a balanced JSON object.
      private def split_json_frontmatter(content : String) : {String, String}?
        end_idx = Hwaro::Utils::FrontmatterScanner.find_json_end(content)
        return unless end_idx

        json_str = content[0, end_idx]
        body = content[end_idx..].lchop("\r\n").lchop("\n")
        {json_str, body}
      end

      private def yaml_to_toml(content : String) : String?
        # Extract YAML frontmatter
        if match = content.match(/\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m)
          yaml_str = match[1]
          body = match[2]

          begin
            yaml_data = YAML.parse(yaml_str)
            toml_str = convert_yaml_to_toml_string(yaml_data)

            "#{TOML_DELIMITER}\n#{toml_str}#{TOML_DELIMITER}\n#{body}"
          rescue ex
            Logger.debug "YAML parse error: #{ex.message}"
            nil
          end
        end
      end

      private def toml_to_yaml(content : String) : String?
        # Extract TOML frontmatter
        if match = content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m)
          toml_str = match[1]
          body = match[2]

          begin
            toml_data = TOML.parse(toml_str)
            yaml_str = convert_toml_to_yaml_string(toml_data)

            "#{YAML_DELIMITER}\n#{yaml_str}#{YAML_DELIMITER}\n#{body}"
          rescue ex
            Logger.debug "TOML parse error: #{ex.message}"
            nil
          end
        end
      end

      private def yaml_to_json(content : String) : String?
        if match = content.match(/\A---\s*\n(.*?\n?)^---\s*$\n?(.*)\z/m)
          yaml_str = match[1]
          body = match[2]
          begin
            yaml_data = YAML.parse(yaml_str)
            json_str = yaml_to_json_string(yaml_data)
            "#{json_str}\n#{body}"
          rescue ex
            Logger.debug "YAML parse error: #{ex.message}"
            nil
          end
        end
      end

      private def toml_to_json(content : String) : String?
        if match = content.match(/\A\+\+\+\s*\n(.*?\n?)^\+\+\+\s*$\n?(.*)\z/m)
          toml_str = match[1]
          body = match[2]
          begin
            toml_data = TOML.parse(toml_str)
            json_str = toml_to_json_string(toml_data)
            "#{json_str}\n#{body}"
          rescue ex
            Logger.debug "TOML parse error: #{ex.message}"
            nil
          end
        end
      end

      private def json_to_yaml(content : String) : String?
        return unless parts = split_json_frontmatter(content)
        json_str, body = parts
        begin
          json_data = JSON.parse(json_str)
          yaml_body = convert_json_to_yaml_string(json_data)
          "#{YAML_DELIMITER}\n#{yaml_body}#{YAML_DELIMITER}\n#{body}"
        rescue ex
          Logger.debug "JSON parse error: #{ex.message}"
          nil
        end
      end

      private def json_to_toml(content : String) : String?
        return unless parts = split_json_frontmatter(content)
        json_str, body = parts
        begin
          json_data = JSON.parse(json_str)
          # Reuse the YAML→TOML builder by going through YAML::Any.
          yaml_any = json_to_yaml_any(json_data)
          toml_body = TomlBuilder.new.build(yaml_any)
          "#{TOML_DELIMITER}\n#{toml_body}#{TOML_DELIMITER}\n#{body}"
        rescue ex
          Logger.debug "JSON parse error: #{ex.message}"
          nil
        end
      end

      # Pretty-print a YAML::Any tree as a JSON object (2-space indent).
      private def yaml_to_json_string(yaml : YAML::Any) : String
        return "{}" unless yaml.as_h?
        yaml_any_to_json_any(yaml).to_pretty_json
      end

      # Pretty-print a TOML::Table as a JSON object (2-space indent).
      private def toml_to_json_string(toml : TOML::Table) : String
        root = JSON::Any.new({} of String => JSON::Any)
        hash = root.as_h
        toml.each do |key, value|
          hash[key] = toml_any_to_json_any(value)
        end
        root.to_pretty_json
      end

      private def yaml_any_to_json_any(yaml : YAML::Any) : JSON::Any
        raw = yaml.raw
        case raw
        when Bool    then JSON::Any.new(raw)
        when Int32   then JSON::Any.new(raw.to_i64)
        when Int64   then JSON::Any.new(raw)
        when Float32 then JSON::Any.new(raw.to_f64)
        when Float64 then JSON::Any.new(raw)
        when String  then JSON::Any.new(raw)
        when Time    then JSON::Any.new(raw.to_rfc3339)
        when Nil     then JSON::Any.new(nil)
        when Array
          arr = yaml.as_a.map { |v| yaml_any_to_json_any(v) }
          JSON::Any.new(arr)
        when Hash
          hash = {} of String => JSON::Any
          yaml.as_h.each do |k, v|
            key_str = k.as_s? || k.to_s
            hash[key_str] = yaml_any_to_json_any(v)
          end
          JSON::Any.new(hash)
        else
          JSON::Any.new(yaml.to_s)
        end
      end

      private def toml_any_to_json_any(value : TOML::Any) : JSON::Any
        raw = value.raw
        case raw
        when Bool    then JSON::Any.new(raw)
        when Int64   then JSON::Any.new(raw)
        when Float64 then JSON::Any.new(raw)
        when String  then JSON::Any.new(raw)
        when Time    then JSON::Any.new(raw.to_rfc3339)
        when Array
          arr = raw.map do |item|
            item.is_a?(TOML::Any) ? toml_any_to_json_any(item) : JSON::Any.new(item.to_s)
          end
          JSON::Any.new(arr)
        when Hash
          if raw.is_a?(Hash(String, TOML::Any))
            hash = {} of String => JSON::Any
            raw.each do |k, v|
              hash[k] = toml_any_to_json_any(v)
            end
            JSON::Any.new(hash)
          else
            JSON::Any.new(raw.to_s)
          end
        else
          JSON::Any.new(value.to_s)
        end
      end

      # Convert JSON::Any to YAML::Any so the existing TomlBuilder can consume it.
      private def json_to_yaml_any(json : JSON::Any) : YAML::Any
        raw = json.raw
        case raw
        when Bool    then YAML::Any.new(raw)
        when Int64   then YAML::Any.new(raw)
        when Float64 then YAML::Any.new(raw)
        when String  then YAML::Any.new(raw)
        when Nil     then YAML::Any.new(nil)
        when Array
          arr = json.as_a.map { |v| json_to_yaml_any(v) }
          YAML::Any.new(arr)
        when Hash
          hash = {} of YAML::Any => YAML::Any
          json.as_h.each do |k, v|
            hash[YAML::Any.new(k)] = json_to_yaml_any(v)
          end
          YAML::Any.new(hash)
        else
          YAML::Any.new(json.to_s)
        end
      end

      # Produce the body of a YAML block (without the `---` fences) for a JSON
      # document by routing through the existing YAML converter.
      private def convert_json_to_yaml_string(json : JSON::Any) : String
        yaml_any = json_to_yaml_any(json)
        # Build a hash like the TOML path does so we get identical formatting.
        hash = {} of String => YAML::Any
        if h = yaml_any.as_h?
          h.each do |k, v|
            key_str = k.as_s? || k.to_s
            hash[key_str] = v
          end
        end
        hash.to_yaml.lchop("---\n")
      end

      private def convert_yaml_to_toml_string(yaml : YAML::Any, indent : Int32 = 0) : String
        TomlBuilder.new.build(yaml)
      end

      private class TomlBuilder
        def initialize
          @output = String::Builder.new
        end

        def build(yaml : YAML::Any) : String
          return "" unless yaml.as_h?
          process_table(yaml, [] of String, true)
          @output.to_s
        end

        private def process_table(yaml : YAML::Any, path : Array(String), print_header : Bool)
          return unless yaml.as_h?

          simple_values = {} of String => YAML::Any
          tables = {} of String => YAML::Any
          array_tables = {} of String => YAML::Any

          yaml.as_h.each do |key, value|
            key_str = key.as_s? || key.to_s

            if value.as_h?
              tables[key_str] = value
            elsif array_of_tables?(value)
              array_tables[key_str] = value
            else
              simple_values[key_str] = value
            end
          end

          if !simple_values.empty? && print_header && !path.empty?
            @output << "\n" unless @output.empty?
            @output << "[" << format_path(path) << "]\n"
          end

          simple_values.each do |k, v|
            @output << format_key(k) << " = " << to_toml_value(v) << "\n"
          end

          tables.each do |k, v|
            process_table(v, path + [k], true)
          end

          array_tables.each do |k, v|
            v.as_a.each do |item|
              new_path = path + [k]
              @output << "\n" unless @output.empty?
              @output << "[[" << format_path(new_path) << "]]\n"
              process_table(item, new_path, false)
            end
          end
        end

        private def array_of_tables?(value : YAML::Any) : Bool
          return false unless value.as_a?
          return false if value.as_a.empty?
          value.as_a.all?(&.as_h?)
        end

        private def format_path(path : Array(String)) : String
          path.map { |k| format_key(k) }.join(".")
        end

        private def format_key(key : String) : String
          if key =~ /^[A-Za-z0-9_-]+$/
            key
          else
            "\"#{escape_toml_string(key)}\""
          end
        end

        private def to_toml_value(value : YAML::Any) : String
          raw = value.raw

          case raw
          when Bool
            raw.to_s
          when Int32, Int64
            raw.to_s
          when Float32, Float64
            raw.to_s
          when Time
            raw.to_rfc3339
          when Array
            items = value.as_a.map { |v| to_toml_value(v) }
            "[#{items.join(", ")}]"
          when String
            "\"#{escape_toml_string(raw)}\""
          when Nil
            "\"\""
          else
            "\"#{escape_toml_string(value.to_s)}\""
          end
        end

        private def escape_toml_string(str : String) : String
          str
            .gsub("\\", "\\\\")
            .gsub("\"", "\\\"")
            .gsub("\n", "\\n")
            .gsub("\t", "\\t")
            .gsub("\r", "\\r")
        end
      end

      private def convert_toml_to_yaml_string(toml : TOML::Table) : String
        yaml_hash = toml_to_hash(toml)
        yaml_hash.to_yaml.lchop("---\n")
      end

      private def toml_to_hash(toml : TOML::Table) : Hash(String, YAML::Any)
        result = {} of String => YAML::Any

        toml.each do |key, value|
          result[key] = toml_value_to_yaml(value)
        end

        result
      end

      private def toml_value_to_yaml(value : TOML::Any) : YAML::Any
        raw = value.raw

        case raw
        when String
          YAML::Any.new(raw)
        when Int64
          YAML::Any.new(raw)
        when Float64
          YAML::Any.new(raw)
        when Bool
          YAML::Any.new(raw)
        when Time
          YAML::Any.new(raw.to_rfc3339)
        when Array
          arr = raw.map { |item|
            if item.is_a?(TOML::Any)
              toml_value_to_yaml(item)
            else
              YAML::Any.new(item.to_s)
            end
          }
          YAML::Any.new(arr)
        when Hash
          if raw.is_a?(Hash(String, TOML::Any))
            hash = {} of YAML::Any => YAML::Any
            raw.each do |k, v|
              hash[YAML::Any.new(k)] = toml_value_to_yaml(v)
            end
            YAML::Any.new(hash)
          else
            YAML::Any.new(raw.to_s)
          end
        else
          YAML::Any.new(raw.to_s)
        end
      end
    end
  end
end
