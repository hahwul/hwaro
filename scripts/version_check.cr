require "yaml"

# Extract version from shard.yml
def get_shard_version : String?
  shard = YAML.parse(File.read("shard.yml"))
  shard["version"].as_s
rescue
  nil
end

# Extract VERSION from src/hwaro.cr
def get_hwaro_version : String?
  content = File.read("src/hwaro.cr")
  match = content.match(/VERSION\s*=\s*"([^"]+)"/)
  match ? match[1] : nil
rescue
  nil
end

# Extract version from snapcraft.yaml
def get_snapcraft_version : String?
  snapcraft = YAML.parse(File.read("snap/snapcraft.yaml"))
  snapcraft["version"].as_s
rescue
  nil
end

# Extract version from spec/hwaro_spec.cr
def get_spec_version : String?
  content = File.read("spec/hwaro_spec.cr")
  match = content.match(/VERSION\.should eq\("([^"]+)"\)/)
  match ? match[1] : nil
rescue
  nil
end

# Extract version from flake.nix
def get_flake_version : String?
  content = File.read("flake.nix")
  match = content.match(/version\s*=\s*"([^"]+)"/)
  match ? match[1] : nil
rescue
  nil
end

# Extract pkgver from aur/PKGBUILD
def get_pkgbuild_version : String?
  content = File.read("aur/PKGBUILD")
  match = content.match(/^pkgver=([\d.]+)/m)
  match ? match[1] : nil
rescue
  nil
end

# Main logic
shard_v = get_shard_version
hwaro_v = get_hwaro_version
snapcraft_v = get_snapcraft_version
spec_v = get_spec_version
flake_v = get_flake_version
pkgbuild_v = get_pkgbuild_version

puts "Shard version: #{shard_v || "Not found"}"
puts "Hwaro version: #{hwaro_v || "Not found"}"
puts "Snapcraft version: #{snapcraft_v || "Not found"}"
puts "Spec version: #{spec_v || "Not found"}"
puts "Flake version: #{flake_v || "Not found"}"
puts "PKGBUILD version: #{pkgbuild_v || "Not found"}"

versions = [shard_v, hwaro_v, snapcraft_v, spec_v, flake_v, pkgbuild_v].compact

if versions.empty?
  puts "No versions found!"
  exit 1
end

unique_versions = versions.uniq

if unique_versions.size == 1
  puts "All versions match: #{unique_versions.first}"
else
  puts "Versions do not match!"
  puts "Unique versions found: #{unique_versions.join(", ")}"
  exit 1
end
