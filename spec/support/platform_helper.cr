# The built CLI that functional specs spawn: `bin/hwaro`, `bin/hwaro.exe` on
# Windows. Build it with `shards build` first.
def hwaro_binary : String
  File.expand_path("../../bin/hwaro", __DIR__) + ({{ flag?(:windows) }} ? ".exe" : "")
end

# Marks the running example pending on Windows, where the POSIX behaviour it
# pins (chmod-based permissions, renaming over an open file, `\` in a file
# name, signals, `sh` syntax) doesn't exist. `why` documents the call site;
# Crystal's spec runner doesn't print pending messages.
def posix_only!(why : String) : Nil
  {% if flag?(:windows) %}
    pending!("POSIX only: #{why}")
  {% end %}
end
