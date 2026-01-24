require "yaml"

# Version file locations
SHARD_FILE     = "shard.yml"
HWARO_FILE     = "src/hwaro.cr"
SNAPCRAFT_FILE = "snap/snapcraft.yaml"
SPEC_FILE      = "spec/hwaro_spec.cr"

# Extract version from shard.yml
def get_shard_version : String?
  begin
    shard = YAML.parse(File.read(SHARD_FILE))
    shard["version"].as_s
  rescue
    nil
  end
end

# Extract VERSION from src/hwaro.cr
def get_hwaro_version : String?
  begin
    content = File.read(HWARO_FILE)
    match = content.match(/VERSION\s*=\s*"([^"]+)"/)
    match ? match[1] : nil
  rescue
    nil
  end
end

# Extract version from snapcraft.yaml
def get_snapcraft_version : String?
  begin
    snapcraft = YAML.parse(File.read(SNAPCRAFT_FILE))
    snapcraft["version"].as_s
  rescue
    nil
  end
end

# Extract version from spec/hwaro_spec.cr
def get_spec_version : String?
  begin
    content = File.read(SPEC_FILE)
    match = content.match(/VERSION\.should eq\("([^"]+)"\)/)
    match ? match[1] : nil
  rescue
    nil
  end
end

# Update shard.yml version
def update_shard_version(new_version : String) : Bool
  begin
    content = File.read(SHARD_FILE)
    updated = content.gsub(/^(version:\s*)[\d.]+/m, "\\1#{new_version}")
    File.write(SHARD_FILE, updated)
    true
  rescue ex
    puts "  Error updating #{SHARD_FILE}: #{ex.message}"
    false
  end
end

# Update src/hwaro.cr VERSION
def update_hwaro_version(new_version : String) : Bool
  begin
    content = File.read(HWARO_FILE)
    updated = content.gsub(/VERSION\s*=\s*"[^"]+"/, "VERSION = \"#{new_version}\"")
    File.write(HWARO_FILE, updated)
    true
  rescue ex
    puts "  Error updating #{HWARO_FILE}: #{ex.message}"
    false
  end
end

# Update snapcraft.yaml version
def update_snapcraft_version(new_version : String) : Bool
  begin
    content = File.read(SNAPCRAFT_FILE)
    updated = content.gsub(/^(version:\s*)['"]?[\d.]+['"]?/m, "\\1#{new_version}")
    File.write(SNAPCRAFT_FILE, updated)
    true
  rescue ex
    puts "  Error updating #{SNAPCRAFT_FILE}: #{ex.message}"
    false
  end
end

# Update spec/hwaro_spec.cr version
def update_spec_version(new_version : String) : Bool
  begin
    content = File.read(SPEC_FILE)
    updated = content.gsub(/VERSION\.should eq\("[^"]+"\)/, "VERSION.should eq(\"#{new_version}\")")
    File.write(SPEC_FILE, updated)
    true
  rescue ex
    puts "  Error updating #{SPEC_FILE}: #{ex.message}"
    false
  end
end

# Validate version format (semver-like: X.Y.Z)
def valid_version?(version : String) : Bool
  !!(version =~ /^\d+\.\d+\.\d+$/)
end

# Main logic
puts "=" * 50
puts "Hwaro Version Update Tool"
puts "=" * 50
puts

# Show current versions
shard_v = get_shard_version
hwaro_v = get_hwaro_version
snapcraft_v = get_snapcraft_version
spec_v = get_spec_version

puts "Current versions:"
puts "  #{SHARD_FILE.ljust(25)} #{shard_v || "Not found"}"
puts "  #{HWARO_FILE.ljust(25)} #{hwaro_v || "Not found"}"
puts "  #{SNAPCRAFT_FILE.ljust(25)} #{snapcraft_v || "Not found"}"
puts "  #{SPEC_FILE.ljust(25)} #{spec_v || "Not found"}"
puts

# Check if versions match
versions = [shard_v, hwaro_v, snapcraft_v, spec_v].compact
unique_versions = versions.uniq

if unique_versions.size > 1
  puts "⚠️  Warning: Versions do not match!"
  puts "   Unique versions found: #{unique_versions.join(", ")}"
  puts
end

current_version = shard_v || hwaro_v || snapcraft_v || "unknown"
puts "Current version: #{current_version}"
puts

# Get new version from user
print "Enter new version (or press Enter to cancel): "
input = gets
new_version = input.try(&.strip) || ""

if new_version.empty?
  puts "Cancelled."
  exit 0
end

unless valid_version?(new_version)
  puts "❌ Invalid version format. Please use semantic versioning (e.g., 1.2.3)"
  exit 1
end

if new_version == current_version
  puts "⚠️  New version is the same as current version. No changes made."
  exit 0
end

puts
puts "Updating to version #{new_version}..."
puts

# Update all files
success_count = 0
total_count = 0

if shard_v
  total_count += 1
  print "  Updating #{SHARD_FILE}... "
  if update_shard_version(new_version)
    puts "✓"
    success_count += 1
  else
    puts "✗"
  end
end

if hwaro_v
  total_count += 1
  print "  Updating #{HWARO_FILE}... "
  if update_hwaro_version(new_version)
    puts "✓"
    success_count += 1
  else
    puts "✗"
  end
end

if snapcraft_v
  total_count += 1
  print "  Updating #{SNAPCRAFT_FILE}... "
  if update_snapcraft_version(new_version)
    puts "✓"
    success_count += 1
  else
    puts "✗"
  end
end

if spec_v
  total_count += 1
  print "  Updating #{SPEC_FILE}... "
  if update_spec_version(new_version)
    puts "✓"
    success_count += 1
  else
    puts "✗"
  end
end

puts
if success_count == total_count
  puts "✅ All #{success_count} files updated successfully to version #{new_version}"
else
  puts "⚠️  Updated #{success_count}/#{total_count} files"
  exit 1
end
