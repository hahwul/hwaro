# Menu tree builder for Hwaro's first-class menu system.
#
# Two sources feed a named menu:
#   - config `[[menus.<name>]]` entries (and their per-language
#     `[[languages.<code>.menus.<name>]]` overrides)
#   - front-matter `menus`/`menu` registrations on pages/sections
#
# `Menus.build` resolves both into `{language => {menu_name => [Entry, ...]}}`
# trees, ready for template exposure (`site.menus` / `get_menu()`, see
# `build_global_vars` in render.cr).

require "../models/config"
require "../models/page"
require "../models/section"
require "../utils/logger"

module Hwaro
  module Content
    module Menus
      # A single resolved menu item. `url` is a bare root-relative path (or
      # an untouched external URL) — comparable to `page.url` for the
      # `active_path` filter. Template exposure additionally computes `href`
      # (`config.with_base_path(url)`) so links work under a subpath deploy;
      # see `build_global_vars`.
      class Entry
        property name : String
        property url : String
        property identifier : String
        property weight : Int32
        property parent : String?
        property external : Bool
        property page_path : String?
        property children : Array(Entry)

        def initialize(
          @name : String,
          @url : String,
          @identifier : String,
          @weight : Int32,
          @parent : String?,
          @external : Bool,
          @page_path : String?,
          @children : Array(Entry) = [] of Entry,
        )
        end
      end

      # Builds the full set of menu trees for every language the site
      # declares (the default language plus every `[languages.*]` key).
      #
      # Deterministic by construction: config entries keep their file
      # declaration order, front-matter registrations are folded in
      # `path`-sorted order, and `assemble_tree` sorts every level by
      # `{weight, name, identifier}`.
      def self.build(config : Models::Config, pages : Array(Models::Page), sections : Array(Models::Section)) : Hash(String, Hash(String, Array(Entry)))
        default_lang = config.default_language
        languages = ([default_lang] + config.languages.keys.sort!).uniq
        content = (pages + sections).sort_by(&.path)

        result = {} of String => Hash(String, Array(Entry))
        languages.each do |lang|
          result[lang] = build_for_language(config, content, lang, default_lang)
        end
        result
      end

      # Builds every named menu for a single language.
      private def self.build_for_language(config : Models::Config, content : Array(Models::Page), lang : String, default_lang : String) : Hash(String, Array(Entry))
        menu_defs = config.language(lang).try(&.menus) || config.menus

        # menu_name => flat candidate list, before tree assembly.
        flat = {} of String => Array(Entry)

        menu_defs.each do |menu_name, items|
          list = flat[menu_name] ||= [] of Entry
          items.each do |item|
            list << Entry.new(
              name: item.name,
              url: item.url,
              identifier: item.identifier,
              weight: item.weight,
              parent: item.parent,
              external: false, # resolved by normalize_urls!
              page_path: nil,
            )
          end
        end

        content.each do |p|
          next if p.menus.empty?
          # A headless page (`render = false`) is never written, so a menu
          # entry pointing at its URL would be a dead link.
          next unless p.render
          next unless (p.language || default_lang) == lang

          p.menus.each do |menu_name, reg|
            list = flat[menu_name] ||= [] of Entry
            name = reg.name || p.title
            list << Entry.new(
              name: name,
              url: p.url,
              identifier: reg.identifier || name,
              weight: reg.weight || 0,
              parent: reg.parent,
              external: false, # resolved by normalize_urls!
              page_path: p.path,
            )
          end
        end

        menus = {} of String => Array(Entry)
        flat.each do |menu_name, entries|
          normalize_urls!(entries)
          menus[menu_name] = assemble_tree(entries, menu_name)
        end
        menus
      end

      # Normalizes each entry's `url` in place and flags `external`.
      # Root-relative (internal) URLs get a leading `/` and a trailing `/`
      # unless the last path segment contains a `.` (an extension, e.g.
      # `/feed.xml`, `/robots.txt`). External URLs (`http://`, `https://`,
      # `//`) are left untouched — they aren't comparable to `page.url`.
      private def self.normalize_urls!(entries : Array(Entry))
        entries.each do |entry|
          url = entry.url
          if external_url?(url)
            entry.external = true
            next
          end

          url = "/#{url}" unless url.starts_with?("/")
          # Don't force a trailing slash onto URLs carrying a query or
          # fragment (`/search?q=x`, `/#contact`) — appending `/` there
          # corrupts the link and breaks `active_path` matching.
          unless url.ends_with?("/") || url.includes?('?') || url.includes?('#')
            last_segment = url.split("/").last? || ""
            url = "#{url}/" unless last_segment.includes?(".")
          end
          entry.url = url
        end
      end

      private def self.external_url?(url : String) : Bool
        url.starts_with?("http://") || url.starts_with?("https://") || url.starts_with?("//")
      end

      # Assembles a flat entry list into a parent/child tree keyed by
      # `identifier`.
      #
      # - A duplicate identifier keeps the LAST declared entry (warns); the
      #   earlier one is dropped rather than shown twice under one identity.
      # - An entry whose `parent` references an identifier that doesn't
      #   exist (or would form a parent cycle) is promoted to the root
      #   rather than dropped or failing the build (warns).
      # - Every level is sorted by `{weight, name, identifier}` so output is
      #   reproducible across builds/workers.
      private def self.assemble_tree(entries : Array(Entry), menu_name : String) : Array(Entry)
        by_identifier = {} of String => Entry
        entries.each do |entry|
          if by_identifier.has_key?(entry.identifier)
            Logger.warn "Menu '#{menu_name}': duplicate identifier '#{entry.identifier}' — the last declaration wins."
          end
          by_identifier[entry.identifier] = entry
        end

        roots = [] of Entry
        by_identifier.each_value do |entry|
          parent_id = entry.parent
          if parent_id.nil? || parent_id.empty?
            roots << entry
            next
          end

          parent = by_identifier[parent_id]?
          if parent.nil?
            Logger.warn "Menu '#{menu_name}': entry '#{entry.identifier}' references unknown parent '#{parent_id}' — promoted to root."
            roots << entry
          elsif creates_cycle?(entry, parent, by_identifier)
            Logger.warn "Menu '#{menu_name}': entry '#{entry.identifier}' has a cyclic parent chain via '#{parent_id}' — promoted to root."
            roots << entry
          else
            parent.children << entry
          end
        end

        sort_tree!(roots)
        roots
      end

      # True when attaching `entry` under `starting_at` would create a
      # parent cycle (`starting_at`'s own ancestor chain loops back to
      # `entry`). Without this guard a 2-entry mutual-parent front-matter
      # typo would recurse forever in `sort_tree!`.
      private def self.creates_cycle?(entry : Entry, starting_at : Entry, by_identifier : Hash(String, Entry)) : Bool
        seen = Set{entry.identifier}
        current = starting_at
        loop do
          return true if seen.includes?(current.identifier)
          seen << current.identifier
          parent_id = current.parent
          return false unless parent_id
          next_current = by_identifier[parent_id]?
          return false unless next_current
          current = next_current
        end
      end

      private def self.sort_tree!(entries : Array(Entry))
        entries.sort_by! { |e| {e.weight, e.name, e.identifier} }
        entries.each { |e| sort_tree!(e.children) }
      end
    end
  end
end
