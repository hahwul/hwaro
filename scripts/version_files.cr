# Every file that spells out the release version, shared by version_check.cr
# and version_update.cr. Group 1 of each pattern is the version. Add a line
# here when a new file starts carrying the version.
#
# flake.nix is intentionally absent: it derives both the package version and
# the minimum Crystal from shard.yml at eval time, so there is nothing to drift.
# The Chocolatey nuspec is a template filled from the release tag.
VERSION_FILES = {
  "shard.yml"              => /^version:\s*([\d.]+)/m,
  "src/hwaro.cr"           => /VERSION\s*=\s*"([^"]+)"/,
  "snap/snapcraft.yaml"    => /^version:\s*['"]?([\d.]+)/m,
  "spec/hwaro_spec.cr"     => /VERSION\.should eq\("([^"]+)"\)/,
  "packaging/aur/PKGBUILD" => /^pkgver=([\d.]+)/m,
  # Mirrors the Netlify config `tool platform` generates from Hwaro::VERSION.
  "docs/content/start/tools/platform.md"    => /# HWARO_VERSION = "([^"]+)"/,
  "docs/content/start/tools/platform.ko.md" => /# HWARO_VERSION = "([^"]+)"/,
}

# Versions found in each file; empty when the file or the pattern is missing.
def read_versions : Hash(String, Array(String))
  VERSION_FILES.to_h do |path, pattern|
    found = File.exists?(path) ? File.read(path).scan(pattern).map(&.[1]) : [] of String
    {path, found}
  end
end

# Prints each file's versions and returns the single version they agree on,
# or nil (after reporting why) when a file is missing one or they disagree.
def report_versions : String?
  versions = read_versions
  versions.each { |path, found| puts "  #{path.ljust(42)} #{found.empty? ? "NOT FOUND" : found.uniq.join(", ")}" }

  if (missing = versions.select { |_, found| found.empty? }.keys).present?
    puts "Version not found in: #{missing.join(", ")}"
    return
  end

  unique = versions.values.flatten.uniq!
  return unique.first if unique.size == 1
  puts "Versions do not match: #{unique.join(", ")}"
end
