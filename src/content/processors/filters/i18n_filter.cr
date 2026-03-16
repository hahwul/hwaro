require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module I18nFilters
          def self.register(env : Crinja)
            # Translate filter: {{ "key" | t }}
            # Uses the current page language and loaded translations
            # Falls back to default language, then returns the key itself
            env.filters["t"] = Crinja.filter do
              key = target.to_s

              # Get translations and language from context
              i18n_data = env.resolve("_i18n_translations")
              lang = env.resolve("page_language").to_s
              lang = "en" if lang.empty?
              default_lang = env.resolve("_i18n_default_language").to_s
              default_lang = "en" if default_lang.empty?

              found = false
              result = key

              begin
                lang_hash = i18n_data.as_h
                key_val = Crinja::Value.new(key)

                # Try current language
                lang_val = Crinja::Value.new(lang)
                if lang_entries = lang_hash[lang_val]?
                  if val = lang_entries.as_h[key_val]?
                    result = val.to_s
                    found = true
                  end
                end

                # Fallback to default language
                if !found && lang != default_lang
                  default_val = Crinja::Value.new(default_lang)
                  if default_entries = lang_hash[default_val]?
                    if val = default_entries.as_h[key_val]?
                      result = val.to_s
                      found = true
                    end
                  end
                end
              rescue
                # No translations available
              end

              result
            end

            # Pluralize filter: {{ count | pluralize("item", "items") }}
            env.filters["pluralize"] = Crinja.filter({singular: "", plural: ""}) do
              count = target.as_number.to_i rescue 0
              singular = arguments["singular"].to_s
              plural = arguments["plural"].to_s
              count == 1 ? singular : plural
            end
          end
        end
      end
    end
  end
end
