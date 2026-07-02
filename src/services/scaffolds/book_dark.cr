# Book Dark scaffold - mdBook-style book structure with dark theme
#
# Inherits layout, content, templates, CSS, and JS from Book. The shared
# stylesheet is built from scheme-paired design tokens (see DesignTokens),
# so this preset only appends the forced `color-scheme: dark` rule and
# swaps the highlight config block for the dark-annotated one.

require "./book"

module Hwaro
  module Services
    module Scaffolds
      class BookDark < Book
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::BookDark
        end

        def description : String
          "Book-style structure with chapters, prev/next navigation, and dark theme"
        end

        protected def config_highlight_theme : String
          "github-dark"
        end

        def config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          config = String.build do |str|
            str << base_config(config_title, config_description)
            str << multilingual_config(multilingual_languages)
            str << plugins_config
            str << content_files_config
            str << highlight_dark_config
            str << og_config
            str << search_config
            str << pagination_config
            str << series_config
            str << related_config
            str << sitemap_config
            str << robots_config
            str << llms_config
            str << feeds_config(feed_sections)
            str << permalinks_config
            str << auto_includes_config
            str << assets_config
            str << markdown_config
            str << content_new_config
            str << image_processing_config
            str << build_hooks_config
            str << pwa_config
            str << amp_config
            str << og_auto_image_config
            str << doctor_config
            str << deployment_config
          end
          config
        end

        # Book's sheet is token-paired for both schemes; pinning
        # `color-scheme: dark` at the end of the sheet flips every token
        # to its dark side. No second hand-maintained stylesheet.
        private def css_content : String
          "#{super}\n#{DesignTokens.forced_dark_css}"
        end
      end
    end
  end
end
