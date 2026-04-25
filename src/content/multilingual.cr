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

        # Only strip the first matching language suffix to avoid over-stripping
        # e.g., "post.en.ko.md" should strip ".ko" (if ko matches) but not both
        # Uses string suffix check instead of per-call Regex compilation.
        cleaned = basename
        config.languages.each_key do |code|
          suffix = ".#{code}.md"
          if cleaned.ends_with?(suffix)
            cleaned = "#{cleaned[0, cleaned.size - suffix.size]}.md"
            break
          end
        end
        # Also check default language if no match above
        if cleaned == basename
          suffix = ".#{config.default_language}.md"
          if cleaned.ends_with?(suffix)
            cleaned = "#{cleaned[0, cleaned.size - suffix.size]}.md"
          end
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
          # A group of size 1 has no cross-language variants, just the
          # page itself; leaving `page.translations` empty matches the
          # canonical `{% if page.translations %}` guard from the
          # docs (#486).
          if group_pages.size <= 1
            group_pages.each { |p| p.translations = [] of Models::TranslationLink }
            next
          end

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
