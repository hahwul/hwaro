require "./version_files"

# Usage: crystal run scripts/version_update.cr [-- X.Y.Z]
# Without an argument the new version is read from stdin.

puts "Current versions:"
current = report_versions
puts

new_version = ARGV[0]? || begin
  print "Enter new version (or press Enter to cancel): "
  gets.try(&.strip) || ""
end

if new_version.empty?
  puts "Cancelled."
  exit 0
end

unless new_version.matches?(/^\d+\.\d+\.\d+$/)
  puts "❌ Invalid version format. Please use semantic versioning (e.g., 1.2.3)"
  exit 1
end

if new_version == current
  puts "⚠️  New version is the same as current version. No changes made."
  exit 0
end

VERSION_FILES.each do |path, pattern|
  next unless File.exists?(path)
  content = File.read(path).gsub(pattern) do |text, md|
    from = md.begin(1) - md.begin(0)
    to = md.end(1) - md.begin(0)
    text[0, from] + new_version + text[to..]
  end
  content = content.gsub(/^pkgrel=\d+/m, "pkgrel=1") if path.ends_with?("PKGBUILD")
  File.write(path, content)
end

puts "Updated versions:"
if report_versions == new_version
  puts "✅ All files updated to #{new_version}"
else
  exit 1
end
