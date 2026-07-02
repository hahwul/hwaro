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
    pending_migration = [
      "src/cli/commands/tool/validate_command.cr",
    ]
    offenders = Dir.glob("src/**/*.cr").select do |path|
      next false if path == "src/utils/logger.cr"
      next false if pending_migration.includes?(path)
      File.read(path).includes?(".colorize(")
    end
    offenders.should be_empty
  end

  it "uses only GLYPHS-registry status glyphs in terminal output" do
    banned = ["✔", "✘", "[DEAD]", "└─"]
    pending_migration = [
      "src/cli/commands/tool/validate_command.cr",
      "src/cli/commands/tool/deadlink_command.cr",
    ]
    offenders = output_surface_files.select do |path|
      next false if pending_migration.includes?(path)
      content = File.read(path)
      banned.any? { |glyph| content.includes?(glyph) }
    end
    offenders.should be_empty
  end

  it "does not hand-roll ASCII dash dividers" do
    pending_migration = [
      "src/cli/commands/tool/deadlink_command.cr",
      "src/services/content_lister.cr",
    ]
    allowed = [
      # Profiler table borders are part of its spec-pinned layout.
      "src/utils/profiler.cr",
    ]
    offenders = output_surface_files.select do |path|
      next false if pending_migration.includes?(path) || allowed.includes?(path)
      File.read(path).includes?(%("-" *))
    end
    offenders.should be_empty
  end
end
