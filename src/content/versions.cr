require "crinja"
require "../models/page"
require "../models/section"
require "../models/config"

# Versioned documentation (`[versions]` + `[[versions.list]]`).
#
# Versions are directory-based and modeled on languages: a page belongs to
# the version whose content directory contains it (ReadContent sets
# `page.version`), Utils::PermalinkResolver maps that directory to the
# published URL prefix, and the scoping rules in Transform / Site /
# Menus keep listings, prev/next and breadcrumbs inside one version.
#
# This module owns the cross-page work that needs the whole page set:
#   - `page.version_links` — the switcher rows (counterpart lookup)
#   - the parent-URL redirect stub when `latest_at_root = false`
#   - the Crinja shapes templates read (`page.version`, `versions`)
module Hwaro
  module Content
    module Versions
      extend self

      # "" for the default language, "/<code>" otherwise — the same prefix
      # PermalinkResolver puts in front of every non-default-language URL.
      def lang_prefix(page : Models::Page, config : Models::Config) : String
        lang = page.language
        return "" unless lang && config.multilingual? && lang != config.default_language
        "/#{lang}"
      end

      # Fill `page.version_links` for every versioned page and, when the
      # latest version does NOT render at its parent's root, alias the
      # parent URL (`/docs/`, `/ko/docs/`) to the latest version's root so
      # the natural docs URL never 404s.
      #
      # Counterparts are matched by (version, language, path relative to the
      # version directory) — `docs/v1/install.md` ↔ `docs/v2/install.md`,
      # `docs/v1/install.ko.md` ↔ `docs/v2/install.ko.md`. A headless
      # (`render = false`) counterpart is never written, so it does not
      # count as existing.
      def link!(pages : Array(Models::Page), config : Models::Config) : Nil
        versions = config.versions
        return unless versions.enabled?

        by_key = {} of {String, String?, String} => Models::Page
        roots = {} of {String, String?} => Models::Page
        claimed = Set(String).new
        pages.each do |page|
          claimed << page.url
          version = page.version
          next unless version
          rel = version.relative_path(page.path)
          next unless rel
          by_key[{version.name, page.language, rel}] ||= page
          roots[{version.name, page.language}] ||= page if page.is_a?(Models::Section) && page.section == version.path
        end

        pages.each do |page|
          version = page.version
          next unless version
          rel = version.relative_path(page.path)
          next unless rel

          prefix = lang_prefix(page, config)
          page.version_links = versions.list.map do |other|
            target = by_key[{other.name, page.language, rel}]?
            target = nil if target && !target.render
            url = if target
                    target.url
                  elsif root = roots[{other.name, page.language}]?
                    root.url
                  else
                    versions.root_url(other, prefix)
                  end
            Models::VersionLink.new(other.name, other.label, other.latest, url, !target.nil?, other.same?(version))
          end

          next if versions.latest_at_root || !version.latest
          next unless page.is_a?(Models::Section) && page.section == version.path
          parent = parent_url(page.url, version.name)
          next unless parent
          # A real page at the parent URL (an authored `docs/_index.md`)
          # keeps it; the stub only fills a hole.
          next if claimed.includes?(parent) || page.aliases.includes?(parent)
          page.aliases << parent
        end
      end

      # `/docs/v2/` → `/docs/`, `/ko/v2/` → `/ko/`; nil when the URL was
      # remapped away from the `<name>/` shape (a `[permalinks]` rule).
      private def parent_url(url : String, name : String) : String?
        suffix = "#{name}/"
        return unless url.ends_with?(suffix) && url.size > suffix.size
        url[0, url.size - suffix.size]
      end

      # --- Crinja shapes --------------------------------------------------

      # `page.version` object: {name, label, latest, url}. `url` is the root
      # URL of the version in the page's language.
      def page_version_value(page : Models::Page, config : Models::Config) : Crinja::Value
        version = page.version
        return Crinja::Value.new(nil) unless version
        version_value(version, config.versions.root_url(version, lang_prefix(page, config)))
      end

      def version_value(version : Models::VersionConfig, url : String) : Crinja::Value
        Crinja::Value.new({
          "name"   => Crinja::Value.new(version.name),
          "label"  => Crinja::Value.new(version.label),
          "latest" => Crinja::Value.new(version.latest),
          "url"    => Crinja::Value.new(url),
        })
      end

      def version_links_value(page : Models::Page) : Crinja::Value
        Crinja::Value.new(page.version_links.map { |link| version_link_value(link) })
      end

      def version_link_value(link : Models::VersionLink) : Crinja::Value
        Crinja::Value.new({
          "name"    => Crinja::Value.new(link.name),
          "label"   => Crinja::Value.new(link.label),
          "latest"  => Crinja::Value.new(link.latest),
          "url"     => Crinja::Value.new(link.url),
          "exists"  => Crinja::Value.new(link.exists),
          "current" => Crinja::Value.new(link.current),
        })
      end

      # The global `versions` variable for one language prefix: iterable
      # (`{% for v in versions %}`) AND attribute-addressable
      # (`versions.latest`, `versions.all`, `versions.size`).
      def versions_value(config : Models::Config, lang_prefix : String) : Crinja::Value
        versions = config.versions
        items = versions.list.map { |v| version_value(v, versions.root_url(v, lang_prefix)) }
        latest = versions.latest
        latest_value = latest ? version_value(latest, versions.root_url(latest, lang_prefix)) : Crinja::Value.new(nil)
        Crinja::Value.new(VersionList.new(items, latest_value))
      end

      class VersionList
        include Crinja::Object
        # Indexable gives Crinja everything it asks of a sequence (`each`,
        # `first`, `size`, `[]`), so `{% for %}`, `| first` and `| length`
        # all work on it.
        include Indexable(Crinja::Value)

        getter items : Array(Crinja::Value)
        getter latest : Crinja::Value

        def initialize(@items : Array(Crinja::Value), @latest : Crinja::Value)
        end

        def size : Int32
          @items.size
        end

        def unsafe_fetch(index : Int) : Crinja::Value
          @items.unsafe_fetch(index)
        end

        # Crinja's hash-accessor fallback (`versions["latest"]`) probes
        # `[]?(String)`; route it through the attribute lookup.
        def []?(name : String) : Crinja::Value?
          value = crinja_attribute(Crinja::Value.new(name))
          value.undefined? ? nil : value
        end

        def crinja_attribute(attr : Crinja::Value) : Crinja::Value
          case attr.to_string
          when "latest"         then @latest
          when "all"            then Crinja::Value.new(@items)
          when "size", "length" then Crinja::Value.new(@items.size)
          else                       Crinja::Value.new(Crinja::Undefined.new(attr.to_s))
          end
        end

        def crinja_item(item : Crinja::Value) : Crinja::Value
          raw = item.raw
          if raw.is_a?(Number)
            @items[raw.to_i]? || Crinja::Value.new(Crinja::Undefined.new(item.to_s))
          else
            crinja_attribute(item)
          end
        end
      end
    end
  end
end
