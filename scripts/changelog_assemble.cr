# Merge changelog.d/*.md fragments into CHANGELOG.md's "## Unreleased".
#
#   crystal run scripts/changelog_assemble.cr          # merge + delete fragments
#   crystal run scripts/changelog_assemble.cr -- --check   # validate only
#
# A fragment is a Markdown file made of `### <Category>` headings followed
# by `- ` bullets (see changelog.d/README.md). Bullets are appended to the
# matching category under "## Unreleased" (created after the "# Changelog"
# title when absent), categories in CATEGORY_ORDER, fragments in file-name
# order so the result is deterministic.

CHANGELOG      = "CHANGELOG.md"
FRAGMENT_DIR   = "changelog.d"
CATEGORY_ORDER = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]

check_only = ARGV.includes?("--check")

fragments = Dir.glob(File.join(FRAGMENT_DIR, "*.md")).reject { |f| File.basename(f) == "README.md" }.sort!
if fragments.empty?
  puts "changelog.d: no fragments."
  exit 0
end

# category => bullets (verbatim lines, including nested continuation lines)
collected = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
errors = [] of String

fragments.each do |path|
  category : String? = nil
  File.read_lines(path).each_with_index do |line, i|
    if heading = line.match(/\A###\s+(\w+)\s*\z/)
      category = heading[1]
      errors << "#{path}:#{i + 1}: unknown category '#{category}' (expected one of #{CATEGORY_ORDER.join(", ")})" unless CATEGORY_ORDER.includes?(category)
    elsif line.strip.empty?
      next
    elsif line.starts_with?("- ") || line.starts_with?("  ")
      if cat = category
        collected[cat] << line
      else
        errors << "#{path}:#{i + 1}: bullet before any '### Category' heading"
      end
    else
      errors << "#{path}:#{i + 1}: expected a '### Category' heading or a '- ' bullet"
    end
  end
end

unless errors.empty?
  errors.each { |e| STDERR.puts "error: #{e}" }
  exit 1
end

if check_only
  puts "changelog.d: #{fragments.size} fragment(s) valid (#{collected.values.sum(&.size)} bullet(s))."
  exit 0
end

lines = File.read_lines(CHANGELOG)

# Locate (or create) the Unreleased section: from its heading to the line
# before the next "## " heading.
unreleased_idx = lines.index { |l| l.strip == "## Unreleased" }
unless unreleased_idx
  title_idx = lines.index(&.starts_with?("# ")) || -1
  lines.insert(title_idx + 1, "")
  lines.insert(title_idx + 2, "## Unreleased")
  lines.insert(title_idx + 3, "")
  unreleased_idx = title_idx + 2
end
section_end = lines.index(unreleased_idx + 1, &.starts_with?("## ")) || lines.size

# Existing bullets inside Unreleased, by category, so a fragment's bullets
# land after the ones already there.
section = lines[unreleased_idx...section_end]
# Rebuild the section explicitly: heading, blank, then categories in order
# with existing bullets first and new ones after.
existing = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
current : String? = nil
section[1..].each do |line|
  if heading = line.match(/\A###\s+(\w+)\s*\z/)
    current = heading[1]
  elsif (cat = current) && !line.strip.empty?
    existing[cat] << line
  end
end

rebuilt = ["## Unreleased", ""]
cats = (CATEGORY_ORDER.select { |c| existing.has_key?(c) || collected.has_key?(c) }) +
       (existing.keys - CATEGORY_ORDER)
cats.each do |cat|
  rebuilt << "### #{cat}"
  existing[cat].each { |l| rebuilt << l } if existing.has_key?(cat)
  collected[cat].each { |l| rebuilt << l } if collected.has_key?(cat)
  rebuilt << ""
end

lines = lines[0...unreleased_idx] + rebuilt + lines[section_end..]
File.write(CHANGELOG, lines.join("\n") + "\n")
fragments.each { |f| File.delete(f) }
puts "changelog.d: merged #{fragments.size} fragment(s) into #{CHANGELOG} (#{collected.values.sum(&.size)} bullet(s)) and removed them."
