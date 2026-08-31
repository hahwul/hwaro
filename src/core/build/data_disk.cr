# Disk half of `site.data` assembly: walks `data/**` into a key tree with
# the directory-wins / deeper-paths-first precedence rules the build has
# always used. Extracted from Phases::Initialize#load_data_files so
# non-build callers (`hwaro tool list` planning `[[content.generate]]`
# pages) can assemble the same disk view WITHOUT the build-only halves —
# remote fetching, serve memoization and cache digests stay in the
# Initialize phase.
#
# Behavior contract (verified by the data-loading specs): identical
# key precedence, identical shadow/duplicate warnings, identical
# skip-on-parse-failure leniency.

require "crinja"
require "../../utils/crinja_utils"
require "../../utils/text_utils"
require "../../utils/logger"

module Hwaro
  module Core
    module Build
      module DataDisk
        extend self

        # Tree node used while assembling `site.data` from the `data/`
        # directory. Each node can hold a leaf value (a parsed data file)
        # and/or a map of children (subdirectory entries). When both are
        # present the children win — see `load_tree`.
        class Node
          getter children : Hash(String, Node) = {} of String => Node
          property value : Crinja::Value? = nil
          property source_path : String? = nil
        end

        # Walk `data/**` into a tree. Deeper paths are processed first so
        # directory namespaces are established before any same-stem
        # root-level file can claim the key.
        def load_tree : Node
          root = Node.new
          return root unless Dir.exists?("data")

          entries = [] of {Array(String), String, String}
          Dir.glob("data/**/*.{yml,yaml,json,toml}") do |path|
            next if File.directory?(path)
            rel = Path[path].relative_to("data")
            parts = rel.parts
            stem = Path[parts.last].stem
            dir_parts = parts[0...-1]
            entries << {dir_parts, stem, path}
          end
          entries.sort_by! { |(dir_parts, _, _)| -dir_parts.size }

          entries.each do |(dir_parts, stem, path)|
            value = parse_file(path)
            next unless value

            node = root
            dir_parts.each do |segment|
              node = node.children[segment] ||= Node.new
            end

            existing = node.children[stem]?
            if existing && !existing.children.empty?
              Logger.warn "Data file '#{path}' is shadowed by directory 'data/#{(dir_parts + [stem]).join('/')}/'; directory takes precedence."
              next
            end

            leaf = existing || Node.new
            if prior = leaf.source_path
              Logger.warn "Duplicate data key for 'site.data.#{(dir_parts + [stem]).join('.')}': '#{path}' overwrites '#{prior}'."
            end
            leaf.value = value
            leaf.source_path = path
            node.children[stem] = leaf
            Logger.debug "Loaded data file: #{path} as site.data.#{(dir_parts + [stem]).join('.')}"
          end

          root
        end

        def tree_to_crinja(node : Node) : Crinja::Value
          if node.children.empty?
            node.value || Crinja::Value.new(nil)
          else
            # Invariant: depth-first processing + directory-wins collision
            # handling means a node with children must never also carry a
            # leaf value — the leaf would have been rejected with a warning.
            # Guard here so a future change to the sort or conflict rules
            # fails loudly instead of silently dropping data.
            if source = node.source_path
              raise "load_data_files invariant broken: node at '#{source}' has both leaf value and children"
            end
            converted = {} of String => Crinja::Value
            node.children.each do |k, child|
              converted[k] = tree_to_crinja(child)
            end
            Crinja::Value.new(converted)
          end
        end

        # The disk tree as the `site.data` hash shape (top-level keys only,
        # no remote entries). Convenience for non-build callers.
        def load_hash : Hash(String, Crinja::Value)
          data = {} of String => Crinja::Value
          load_tree.children.each do |key, child|
            data[key] = tree_to_crinja(child)
          end
          data
        end

        private def parse_file(path : String) : Crinja::Value?
          # JSON and TOML both reject a leading BOM outright, so a data file
          # saved by a Windows editor would warn-and-skip and leave
          # `site.data.<key>` undefined — which then fails the whole render.
          content = Utils::TextUtils.strip_bom(File.read(path))
          # The glob feeding this method only matches .yml/.yaml/.json/.toml,
          # so the shared dispatcher's .csv branch is unreachable here —
          # `data/` has never read CSV, and this refactor does not change that.
          Utils::CrinjaUtils.parse_data_string(content, File.extname(path).downcase.lchop('.'))
        rescue ex
          # This rescue also covers read errors and value-conversion failures,
          # not just parse errors, so it must not assert the file is malformed
          # — it once blamed the author for a "parse error" on a TOML file that
          # parsed perfectly. Name the consequence instead: the key disappears
          # from site.data, and templates dereferencing it then fail the whole
          # render.
          Logger.warn "Skipping data file #{path} (site.data entry dropped): #{ex.message}"
          nil
        end
      end
    end
  end
end
