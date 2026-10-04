# The built CLI that functional specs spawn: `bin/hwaro`, `bin/hwaro.exe` on
# Windows. Build it with `shards build` first.
def hwaro_binary : String
  File.expand_path("../../bin/hwaro", __DIR__) + ({{ flag?(:windows) }} ? ".exe" : "")
end
