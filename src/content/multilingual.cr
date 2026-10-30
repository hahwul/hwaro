require "../models/config"
require "../models/page"

module Hwaro
  module Content
    module Multilingual
      extend self

      # Mirrors Core::Build::Phases::ReadContent::PAGE_EXTENSIONS (not
      # required here to avoid pulling the build phases into the content
      # layer). `.md` first so the common case short-circuits.
      PAGE_EXTENSIONS = {".md", ".markdown"}

      # The page extension of `path`, or nil when it is not a page source.
      def page_extension(path : String) : String?
        PAGE_EXTENSIONS.find { |ext| path.ends_with?(ext) }
      end

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
        ext = page_extension(page_path)
        return page_path unless ext

        relative_path = page_path.gsub('\\', '/')
        dir = Path[relative_path].dirname.to_s
        basename = Path[relative_path].basename

        # Only strip the first matching language suffix to avoid over-stripping
        # e.g., "post.en.ko.md" should strip ".ko" (if ko matches) but not both
        # Uses string suffix check instead of per-call Regex compilation.
        cleaned = basename
        config.languages.each_key do |code|
          suffix = ".#{code}#{ext}"
          if cleaned.ends_with?(suffix)
            cleaned = "#{cleaned[0, cleaned.size - suffix.size]}#{ext}"
            break
          end
        end
        # Also check default language if no match above
        if cleaned == basename
          suffix = ".#{config.default_language}#{ext}"
          if cleaned.ends_with?(suffix)
            cleaned = "#{cleaned[0, cleaned.size - suffix.size]}#{ext}"
          end
        end

        dir == "." ? cleaned : "#{dir}/#{cleaned}"
      end

      # A front matter `translation_key` displaced from its group by
      # another page of the same language: `loser` gets no translations of
      # its own and nobody links to it.
      record KeyCollision, key : String, code : String, winner : Models::Page, loser : Models::Page

      # Fill `page.translations` for every page. A page's group is its
      # `translation_key` (scoped to its version, so `v1/` and `v2/` copies
      # sharing a key stay apart) or, without one, its file name minus the
      # language suffix (`about.md` ↔ `about.ko.md`). The two never mix: a
      # keyed page does not join the file-name group of an unkeyed one.
      # Inside a keyed group the first path (byte order) of each language
      # wins; the others are returned so callers can report them.
      def link_translations!(pages : Array(Models::Page), config : Models::Config) : Array(KeyCollision)
        collisions = [] of KeyCollision
        return collisions unless multilingual?(config)

        groups = Hash({String?, String, Bool}, Array(Models::Page)).new { |h, k| h[k] = [] of Models::Page }
        pages.each do |page|
          next unless page_extension(page.path)
          if key = page.translation_key
            groups[{page.version.try(&.name), key, true}] << page
          else
            groups[{nil, translation_key(page.path, config), false}] << page
          end
        end

        order = ordered_language_codes(config)
        default = config.default_language

        groups.each do |(_, key, keyed), group_pages|
          # A group of size 1 has no cross-language variants, just the
          # page itself; leaving `page.translations` empty matches the
          # canonical `{% if page.translations %}` guard from the
          # docs (#486).
          if group_pages.size <= 1
            group_pages.each { |p| p.translations = [] of Models::TranslationLink }
            next
          end

          by_code = {} of String => Models::Page
          if keyed
            group_pages.sort_by!(&.path).each do |p|
              code = language_code(p, config)
              if winner = by_code[code]?
                collisions << KeyCollision.new(key, code, winner, p)
                p.translations = [] of Models::TranslationLink
              else
                by_code[code] = p
              end
            end
            group_pages = by_code.values
          else
            group_pages.each do |p|
              by_code[language_code(p, config)] = p
            end
          end

          group_pages.each do |current_page|
            current_code = language_code(current_page, config)
            links = order.compact_map do |code|
              next unless target = by_code[code]?
              # A headless (`render = false`) translation is never written
              # and a `redirect_to` stub only bounces elsewhere: linking
              # either from the switcher or hreflang advertises a 404 or a
              # non-canonical URL (the sitemap already filters both).
              next if !target.same?(current_page) && (!target.render || target.has_redirect?)
              Models::TranslationLink.new(
                code: code,
                url: target.url,
                title: target.title,
                is_current: code == current_code,
                is_default: code == default
              )
            end
            current_page.translations = links.size > 1 ? links : [] of Models::TranslationLink
          end
        end
        collisions
      end
    end
  end
end
