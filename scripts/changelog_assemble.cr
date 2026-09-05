# Merge changelog.d/*.md fragments into CHANGELOG.md's "## Unreleased".
#
#   crystal run scripts/changelog_assemble.cr             # merge + delete fragments
#   crystal run scripts/changelog_assemble.cr -- --check  # validate only
#
# A fragment is a Markdown file made of `### <Category>` headings followed
# by `- ` bullets (see changelog.d/README.md). The merge is INSERTION-ONLY:
# every existing line of CHANGELOG.md is kept byte-for-byte; a fragment's
# bullets are appended after the last bullet of the matching category in
# "## Unreleased", a category that does not exist yet is added at its
# canonical position (CATEGORY_ORDER), and a missing "## Unreleased" is
# created after the "# Changelog" title. Fenced code blocks are skipped when
# looking for headings. Fragments merge in file-name order, so the result is
# deterministic.

CHANGELOG      = "CHANGELOG.md"
FRAGMENT_DIR   = "changelog.d"
CATEGORY_ORDER = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]

check_only = false
ARGV.each do |arg|
  case arg
  when "--check" then check_only = true
  else
    STDERR.puts "error: unknown argument #{arg.inspect} (accepted: --check)"
    exit 2
  end
end

unless File.exists?(CHANGELOG)
  STDERR.puts "error: #{CHANGELOG} not found (run from the repository root)"
  exit 1
end

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
  bullets = 0
  File.read_lines(path).each_with_index do |raw, i|
    line = raw.chomp('\r')
    if heading = line.match(/\A###\s+(\w+)\s*\z/)
      category = heading[1]
      errors << "#{path}:#{i + 1}: unknown category '#{category}' (expected one of #{CATEGORY_ORDER.join(", ")})" unless CATEGORY_ORDER.includes?(category)
    elsif line.strip.empty?
      next
    elsif line.starts_with?("- ") || line.starts_with?("  ")
      if cat = category
        collected[cat] << line
        bullets += 1
      else
        errors << "#{path}:#{i + 1}: bullet before any '### Category' heading"
      end
    else
      errors << "#{path}:#{i + 1}: expected a '### Category' heading or a '- ' bullet"
    end
  end
  errors << "#{path}: no bullets" if bullets == 0
end

unless errors.empty?
  errors.each { |e| STDERR.puts "error: #{e}" }
  exit 1
end

if check_only
  puts "changelog.d: #{fragments.size} fragment(s) valid (#{collected.values.sum(&.size)} bullet(s))."
  exit 0
end

lines = File.read_lines(CHANGELOG, chomp: false).map(&.chomp)

# Heading detection that ignores fenced code blocks.
def heading_indexes(lines : Array(String), &) : Nil
  in_fence = false
  lines.each_with_index do |line, i|
    in_fence = !in_fence if line.starts_with?("```") || line.starts_with?("~~~")
    next if in_fence
    yield line, i
  end
end

unreleased_idx = nil.as(Int32?)
section_end = lines.size
heading_indexes(lines) do |line, i|
  if unreleased_idx.nil?
    unreleased_idx = i if line.strip == "## Unreleased"
  elsif line.starts_with?("## ")
    section_end = i
    break
  end
end

unless idx = unreleased_idx
  title_idx = lines.index(&.starts_with?("# ")) || -1
  lines.insert(title_idx + 1, "")
  lines.insert(title_idx + 2, "## Unreleased")
  lines.insert(title_idx + 3, "")
  unreleased_idx = idx = title_idx + 2
  section_end = idx + 2
end

# Category headings inside Unreleased: name => heading index (fences skipped).
cat_index = {} of String => Int32
heading_indexes(lines[idx...section_end]) do |line, i|
  if heading = line.match(/\A###\s+(\w+)\s*\z/)
    cat_index[heading[1]] = idx + i
  end
end

# Apply insertions from the bottom up so earlier indexes stay valid.
insertions = [] of {Int32, Array(String)} # {insert_before_index, lines}
cats = CATEGORY_ORDER.select { |c| collected.has_key?(c) }
cats.each do |cat|
  if heading_at = cat_index[cat]?
    # after the last non-blank line of this category block
    j = heading_at + 1
    last = heading_at
    while j < section_end && !lines[j].starts_with?("### ")
      last = j unless lines[j].strip.empty?
      j += 1
    end
    insertions << {last + 1, collected[cat]}
  else
    # new category: before the first existing category that sorts after it,
    # else at the end of the section (before its trailing blank line)
    after = CATEGORY_ORDER.index(cat) || CATEGORY_ORDER.size
    successor = cat_index.select { |name, _| (CATEGORY_ORDER.index(name) || Int32::MAX) > after }.values.min?
    block = ["### #{cat}"] + collected[cat] + [""]
    if successor
      insertions << {successor, block}
    else
      at = section_end
      while at > idx + 1 && lines[at - 1].strip.empty?
        at -= 1
      end
      insertions << {at, [""] + block[0..-2]}
    end
  end
end

insertions.sort_by! { |pos, _| -pos }
insertions.each do |pos, new_lines|
  lines = lines[0...pos] + new_lines + lines[pos..]
end

File.write(CHANGELOG, lines.join("\n") + "\n")
failed = fragments.reject { |f| File.delete?(f) }
unless failed.empty?
  STDERR.puts "error: merged into #{CHANGELOG} but could not delete: #{failed.join(", ")} — remove them by hand; do NOT re-run (it would insert the bullets again)"
  exit 1
end
puts "changelog.d: merged #{fragments.size} fragment(s) into #{CHANGELOG} (#{collected.values.sum(&.size)} bullet(s)) and removed them."
