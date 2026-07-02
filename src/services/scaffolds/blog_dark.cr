# Blog Dark scaffold - blog-focused structure with dark theme
#
# Inherits layout, content, templates, CSS, and JS from the Blog
# scaffold. The shared stylesheet is built from light-dark() token
# pairs (see DesignTokens), so the dark preset only appends
# `forced_dark_css` — a trailing `:root { color-scheme: dark; }` —
# to pin every token to its dark side. The config differs only in
# the highlight theme (github-dark).

require "./blog"

module Hwaro
  module Services
    module Scaffolds
      class BlogDark < Blog
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::BlogDark
        end

        def description : String
          "Blog-focused structure with dark theme"
        end

        protected def config_highlight_theme : String
          "github-dark"
        end

        def config_content(skip_taxonomies : Bool = false, multilingual_languages : Array(String) = [] of String) : String
          config = String.build do |str|
            # Site basics
            str << base_config(config_title, config_description)

            # Content & Processing
            str << multilingual_config(multilingual_languages)
            str << plugins_config
            str << content_files_config
            str << highlight_dark_config
            str << og_config
            str << search_config
            str << pagination_config
            str << series_config
            str << related_config
            str << taxonomies_config unless skip_taxonomies

            # SEO & Feeds
            str << sitemap_config
            str << robots_config
            str << llms_config
            str << feeds_config(feed_sections)

            # Optional features (commented out by default)
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

        private def css_content : String
          "#{super}\n#{DesignTokens.forced_dark_css}"
        end
      end
    end
  end
end
