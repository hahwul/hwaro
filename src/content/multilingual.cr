require "../models/config"
require "../models/page"

module Hwaro
  module Content
    module Multilingual
      extend self

      def multilingual?(config : Models::Config) : Bool
        config.multilingual?
      end

      def language_code(page : Models::Page, config : Models::Config) : String
        page.language || config.default_language
      end

      def ordered_language_codes(config : Models::Config) : Array(String)
        default = config.default_language
        rest = config.sorted_languages.map(&.code).reject { |c| c == default }
        ([default] + rest).uniq
      end

      def translation_key(page_path : String, config : Models::Config) : String
        return page_path unless page_path.ends_with?(".md")

        relative_path = page_path.gsub('\\', '/')
        dir = Path[relative_path].dirname.to_s
        basename = Path[relative_path].basename

        codes = (config.languages.keys + [config.default_language]).uniq
        cleaned = codes.reduce(basename) do |acc, code|
          escaped = Regex.escape(code)
          acc.sub(/\.#{escaped}\.md$/, ".md")
        end

        dir == "." ? cleaned : "#{dir}/#{cleaned}"
      end

      def link_translations!(pages : Array(Models::Page), config : Models::Config)
        return unless multilingual?(config)

        groups = Hash(String, Array(Models::Page)).new { |h, k| h[k] = [] of Models::Page }
        pages.each do |page|
          next unless page.path.ends_with?(".md")
          groups[translation_key(page.path, config)] << page
        end

        order = ordered_language_codes(config)
        default = config.default_language

        groups.each_value do |group_pages|
          by_code = {} of String => Models::Page
          group_pages.each do |p|
            by_code[language_code(p, config)] = p
          end

          group_pages.each do |current_page|
            current_code = language_code(current_page, config)
            current_page.translations = order.compact_map do |code|
              if target = by_code[code]?
                Models::TranslationLink.new(
                  code: code,
                  url: target.url,
                  title: target.title,
                  is_current: code == current_code,
                  is_default: code == default
                )
              end
            end
          end
        end
      end
    end
  end
end
