require "toml"
require "../models/config"
require "../utils/logger"

module Hwaro
  module Content
    module I18n
      extend self

      alias TranslationData = Hash(String, Hash(String, String))

      # Load translation files from i18n directory
      # Looks for TOML files named by language code: i18n/en.toml, i18n/ko.toml, etc.
      def load_translations(i18n_dir : String, config : Models::Config) : TranslationData
        translations = TranslationData.new

        return translations unless Dir.exists?(i18n_dir)

        # Load files for each configured language
        codes = [config.default_language] + config.languages.keys
        codes.uniq.each do |code|
          path = File.join(i18n_dir, "#{code}.toml")
          next unless File.exists?(path)

          begin
            data = TOML.parse(File.read(path))
            flat = {} of String => String
            flatten_toml(data, "", flat)
            translations[code] = flat
          rescue ex
            Logger.warn "  [WARN] Failed to parse i18n file #{path}: #{ex.message}"
          end
        end

        translations
      end

      # Translate a key for a given language, with optional fallback to default language
      def translate(key : String, language : String, translations : TranslationData, default_language : String = "en") : String
        # Try current language
        if lang_data = translations[language]?
          if value = lang_data[key]?
            return value
          end
        end

        # Fallback to default language
        if language != default_language
          if default_data = translations[default_language]?
            if value = default_data[key]?
              return value
            end
          end
        end

        # Return key itself as fallback
        key
      end

      # Pluralize helper: select singular/plural form based on count
      def pluralize(count : Int64 | Int32, singular : String, plural : String) : String
        count == 1 ? singular : plural
      end

      # Flatten nested TOML hash into dot-separated keys
      # e.g. { "nav" => { "home" => "Home" } } → { "nav.home" => "Home" }
      private def flatten_toml(data : TOML::Table, prefix : String, result : Hash(String, String))
        data.each do |key, value|
          full_key = prefix.empty? ? key : "#{prefix}.#{key}"
          case raw = value.raw
          when String
            result[full_key] = raw
          when Hash
            if table = value.as_h?
              flatten_toml(table, full_key, result)
            end
          when Array
            # Store array items as indexed keys (e.g., "nav.items.0", "nav.items.1")
            raw.each_with_index do |item, i|
              toml_item = item.as?(TOML::Any)
              if toml_item
                item_raw = toml_item.raw
                case item_raw
                when String
                  result["#{full_key}.#{i}"] = item_raw
                when Hash
                  if table = toml_item.as_h?
                    flatten_toml(table, "#{full_key}.#{i}", result)
                  end
                else
                  result["#{full_key}.#{i}"] = item_raw.to_s
                end
              else
                result["#{full_key}.#{i}"] = item.to_s
              end
            end
          else
            result[full_key] = raw.to_s
          end
        end
      end
    end
  end
end
