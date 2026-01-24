require "yaml"

# Extract version from shard.yml
def get_shard_version : String?
  begin
    shard = YAML.parse(File.read("shard.yml"))
    shard["version"].as_s
  rescue
    nil
  end
end

# Extract VERSION from src/hwaro.cr
def get_hwaro_version : String?
  begin
    content = File.read("src/hwaro.cr")
    match = content.match(/VERSION\s*=\s*"([^"]+)"/)
    match ? match[1] : nil
  rescue
    nil
  end
end

# Extract version from Dockerfile (LABEL org.opencontainers.image.version="...")
def get_docker_version : String?
  begin
    content = File.read("Dockerfile")
    match = content.match(/LABEL\s+org\.opencontainers\.image\.version\s*=\s*"([^"]+)"/)
    match ? match[1] : nil
  rescue
    nil
  end
end

# Extract version from snapcraft.yaml
def get_snapcraft_version : String?
  begin
    snapcraft = YAML.parse(File.read("snap/snapcraft.yaml"))
    snapcraft["version"].as_s
  rescue
    nil
  end
end

# Extract version from spec/hwaro_spec.cr
def get_spec_version : String?
  begin
    content = File.read("spec/hwaro_spec.cr")
    match = content.match(/VERSION\.should eq\("([^"]+)"\)/)
    match ? match[1] : nil
  rescue
    nil
  end
end

# Main logic
shard_v = get_shard_version
hwaro_v = get_hwaro_version
docker_v = get_docker_version
snapcraft_v = get_snapcraft_version
spec_v = get_spec_version

puts "Shard version: #{shard_v || "Not found"}"
puts "Hwaro version: #{hwaro_v || "Not found"}"
puts "Docker version: #{docker_v || "Not found"}"
puts "Snapcraft version: #{snapcraft_v || "Not found"}"
puts "Spec version: #{spec_v || "Not found"}"

versions = [shard_v, hwaro_v, docker_v, snapcraft_v, spec_v].compact

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
