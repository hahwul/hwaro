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
        stem = Path[relative_path].basename.rchop(ext)
        code = Utils::PathUtils.language_suffix(stem) do |suffix|
          config.languages.has_key?(suffix) || suffix == config.default_language
        end
        stem = stem.rchop(".#{code}") if code
        dir == "." ? "#{stem}#{ext}" : "#{dir}/#{stem}#{ext}"
      end

      def normalize_markdown_extension(path : String) : String
        path.ends_with?(".markdown") ? path.rchop(".markdown") + ".md" : path
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
      # Inside a keyed group each language keeps one page — a linkable one
      # (rendered, not a redirect stub) before any other, then the first
      # path in byte order; the others are returned so callers can report
      # them.
      #
      # `unwritten` holds the paths of pages that lose their output URL to
      # another page (the build's output-path collisions). Such a page is no
      # more linkable than a headless one: its URL serves the page that won
      # it, so a switcher row or hreflang alternate naming it sent readers
      # and search engines to unrelated content.
      def link_translations!(pages : Array(Models::Page), config : Models::Config, unwritten : Set(String) = Set(String).new) : Array(KeyCollision)
        collisions = [] of KeyCollision
        return collisions unless multilingual?(config)
        linkable = ->(p : Models::Page) { p.render && !p.has_redirect? && !unwritten.includes?(p.path) }

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

        # Pair mixed extensions when there is one page per language.
        # Keep exact-extension groups when both spellings have authored
        # pages in the same language (they can have distinct custom URLs).
        groups.reject! do |(version, key, keyed), variants|
          next false if keyed || !key.ends_with?(".markdown")
          next false unless matching = groups[{version, normalize_markdown_extension(key), false}]?
          codes = matching.map { |p| language_code(p, config) }.to_set
          next false if variants.any? { |p| codes.includes?(language_code(p, config)) }
          matching.concat(variants)
          true
        end

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
            # A linkable page (written, not a redirect stub) beats one the
            # links below would skip anyway, so a headless duplicate never
            # leaves its language unlinked; then the first path wins.
            group_pages.sort_by! { |p| {linkable.call(p) ? 0 : 1, p.path} }.each do |p|
              code = language_code(p, config)
              if winner = by_code[code]?
                # A headless, redirecting or unwritten page is never linked anyway.
                collisions << KeyCollision.new(key, code, winner, p) if linkable.call(p)
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
              # non-canonical URL (the sitemap already filters both). An
              # unwritten one names another page's URL.
              next if !target.same?(current_page) && !linkable.call(target)
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
