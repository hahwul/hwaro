require "../spec_helper"

# Design-lint for the ember terminal identity (see src/utils/logger.cr).
#
# All terminal styling must flow through Logger's Role palette and GLYPHS
# registry so every command renders the same visual language. These specs
# mechanically prevent the drift they eliminated: raw colorize calls,
# off-registry status glyphs, and hand-rolled ASCII dividers.
#
# PENDING_* lists name files whose migration is staged in a follow-up
# commit; shrink them as commands move onto the ember primitives. Never
# add a new file to them.

# Output-surface sources: CLI commands, shared utils, and top-level
# services (scaffolds/ and defaults/ emit *site* content, not terminal
# output, so they are out of scope).
OUTPUT_SURFACE_GLOBS = [
  "src/cli/**/*.cr",
  "src/utils/*.cr",
  "src/core/**/*.cr",
  "src/services/*.cr",
]

def output_surface_files : Array(String)
  OUTPUT_SURFACE_GLOBS.flat_map { |g| Dir.glob(g) }.uniq!.sort!
end

describe "terminal style lint" do
  it "routes every color through Logger (no raw .colorize outside logger.cr)" do
    offenders = Dir.glob("src/**/*.cr").select do |path|
      next false if path == "src/utils/logger.cr"
      File.read(path).includes?(".colorize(")
    end
    offenders.should be_empty
  end

  it "uses only GLYPHS-registry status glyphs in terminal output" do
    # ▴ and ● are retired Minimal Spark predecessors — they must not creep
    # back in anywhere, not even logger.cr.
    banned = ["✔", "✘", "[DEAD]", "▴", "●"]
    # Registry glyphs (✦ via :result, tree connectors via :tree_mid /
    # :tree_last); a literal anywhere but the registry itself bypasses the
    # ASCII fallback and the role paint, so they stay banned outside logger.cr.
    registry_only = ["✦", "├─", "└─"]
    offenders = output_surface_files.select do |path|
      content = File.read(path)
      next true if banned.any? { |glyph| content.includes?(glyph) }
      path != "src/utils/logger.cr" && registry_only.any? { |glyph| content.includes?(glyph) }
    end
    offenders.should be_empty
  end

  it "does not hand-roll ASCII or box-drawing dash dividers" do
    allowed = [
      # Profiler table borders are part of its spec-pinned layout.
      "src/utils/profiler.cr",
    ]
    offenders = output_surface_files.select do |path|
      next false if allowed.includes?(path)
      content = File.read(path)
      content.includes?(%("-" *)) || content.includes?(%("─" *))
    end
    offenders.should be_empty
  end
end
