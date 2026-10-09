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

# `names` without the ones Windows cannot store as a file name (`<>:"|?*`, or
# `\` — a separator there), so a spec looping over hostile names still runs
# the rest on Windows.
def storable_file_names(names : Array(String)) : Array(String)
  {% if flag?(:windows) %}
    names.reject(&.matches?(/[<>:"|?*\\]/))
  {% else %}
    names
  {% end %}
end

# The `storable_file_names` a `PathUtils.glob_escape`d directory matches
# literally: on Windows that leaves out braces too (Crystal's brace expansion
# honours no escape there).
def glob_literal_names(names : Array(String)) : Array(String)
  {% if flag?(:windows) %}
    storable_file_names(names).reject(&.matches?(/[{},]/))
  {% else %}
    names
  {% end %}
end
