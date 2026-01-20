# Frontmatter Converter Service
#
# This service provides functionality to convert frontmatter between
# YAML and TOML formats in content files.

require "yaml"
require "toml"
require "../utils/logger"

module Hwaro
  module Services
    # Frontmatter format types
    enum FrontmatterFormat
      YAML
      TOML
      Unknown
    end

    # Result of a conversion operation
    struct ConversionResult
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

      # Detect the frontmatter format of a file
      def detect_format(content : String) : FrontmatterFormat
        if content.starts_with?("#{TOML_DELIMITER}\n") || content.starts_with?("#{TOML_DELIMITER}\r\n")
          FrontmatterFormat::TOML
        elsif content.starts_with?("#{YAML_DELIMITER}\n") || content.starts_with?("#{YAML_DELIMITER}\r\n")
          FrontmatterFormat::YAML
        else
          FrontmatterFormat::Unknown
        end
      end

      # Convert a single file's frontmatter
      def convert_file(file_path : String, target_format : FrontmatterFormat) : Bool
        content = File.read(file_path)
        current_format = detect_format(content)

        # Skip if already in target format or unknown format
        if current_format == target_format
          Logger.info "  Skipped (already #{target_format}): #{file_path}"
          return false
        end

        if current_format == FrontmatterFormat::Unknown
          Logger.warn "  Skipped (no frontmatter): #{file_path}"
          return false
        end

        converted_content = convert_content(content, current_format, target_format)

        if converted_content
          File.write(file_path, converted_content)
          Logger.success "  Converted: #{file_path}"
          true
        else
          Logger.error "  Failed to convert: #{file_path}"
          false
        end
      rescue ex
        Logger.error "  Error converting #{file_path}: #{ex.message}"
        false
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

        format_name = target_format == FrontmatterFormat::YAML ? "YAML" : "TOML"
        Logger.info "Converting frontmatter to #{format_name} format..."
        Logger.info ""

        find_content_files.each do |file_path|
          content = File.read(file_path)
          current_format = detect_format(content)

          if current_format == target_format
            skipped += 1
            next
          end

          if current_format == FrontmatterFormat::Unknown
            skipped += 1
            next
          end

          begin
            converted_content = convert_content(content, current_format, target_format)

            if converted_content
              File.write(file_path, converted_content)
              Logger.success "  Converted: #{file_path}"
              converted += 1
            else
              Logger.error "  Failed: #{file_path}"
              errors += 1
            end
          rescue ex
            Logger.error "  Error: #{file_path} - #{ex.message}"
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
        else
          nil
        end
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
        else
          nil
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
        else
          nil
        end
      end

      private def convert_yaml_to_toml_string(yaml : YAML::Any, indent : Int32 = 0) : String
        return "" unless yaml.as_h?

        result = String::Builder.new

        yaml.as_h.each do |key, value|
          key_str = key.as_s? || key.to_s

          case
          when value.as_h?
            # Nested table - use [section] notation
            result << "[#{key_str}]\n"
            value.as_h.each do |nested_key, nested_value|
              nested_key_str = nested_key.as_s? || nested_key.to_s
              result << "#{nested_key_str} = #{to_toml_value(nested_value)}\n"
            end
          else
            result << "#{key_str} = #{to_toml_value(value)}\n"
          end
        end

        result.to_s
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
