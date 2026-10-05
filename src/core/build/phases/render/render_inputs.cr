# Render phase — the `--cache` key for what templates read outside the
# tracked files.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
#
# The global cache key (Initialize) covers config, templates, data/ and the
# CLI options. Templates also read things none of those cover, so a warm
# build kept serving pages rendered against the old value:
#
#   * build-derived globals — the fingerprinted `asset()` bundle names (the
#     AfterInitialize asset hook produces them AFTER the key is set) and the
#     `[auto_includes]` / local-highlight tags with their `?v=` digest and,
#     under `[assets] sri`, their `integrity` digests;
#   * reads made mid-render — `env()`, `load_data()` of a file outside data/,
#     and the source image behind `resize_image()`.
#
# The second group is only knowable by rendering, so the render records it
# (`TemplateEngine.record_render_read`) and the cache keeps the read KEYS;
# the next warm build re-reads those keys and compares one digest over all
# of it before any page is filtered.
module Hwaro::Core::Build::Phases::Render
  # Digest of the build-derived template globals. Computed once per build.
  private def render_globals_digest(config : Models::Config, cache_busting : Bool) : String
    digest = Digest::SHA256.new
    manifest = Content::Hooks::AssetHooks.manifest
    manifest.keys.sort!.each do |name|
      Utils::DigestUtils.update_length_prefixed(digest, name)
      Utils::DigestUtils.update_length_prefixed(digest, manifest[name])
    end
    cache_bust = cache_busting ? compute_cache_bust(config) : ""
    Utils::DigestUtils.update_length_prefixed(digest, cache_bust)
    # The tag list itself, not just the digest: an empty file added to an
    # auto-include dir adds a `<link>` without moving `?v=`.
    sri_root = sri_root(config)
    Utils::DigestUtils.update_length_prefixed(digest, config.auto_includes.all_tags(config.base_url, cache_bust, sri_root))
    # `[assets] sri` prints a digest of the emitted bytes into the tags; the
    # `?v=` above is "" under --skip-cache-busting and never covers the
    # highlight files' bytes, so fold the tags themselves.
    Utils::DigestUtils.update_length_prefixed(digest, config.highlight.tags(cache_bust, sri_root)) if sri_root
    digest.hexfinal
  end

  # Stored next to the read keys: `stamp:<mtime_ms>:<size>:<md5>:<path>`,
  # one per recorded file. A file whose mtime and size still match its stamp
  # reuses the stamped digest instead of being read — the same mtime fast
  # path `Cache#changed?` takes for content files. Without it every warm
  # build re-hashed every `resize_image()` source: a site with 1.4 GB of
  # photos went from 0.03s to 2.5s for a build that rendered nothing. A
  # touched-but-identical file (a fresh CI checkout) is re-hashed once and
  # still matches, because only the digest — never the stamp — reaches the
  # render-inputs hash.
  private RENDER_INPUT_STAMP_PREFIX = "stamp:"
  # In-memory memo key for the CURRENT stamp of a file (NUL keeps it apart
  # from every real read key).
  private RENDER_INPUT_STAMP_MEMO = "\0stamp:"

  # One digest over the globals and the current value of every read in
  # `keys`. SHA-256 rather than MD5: env values (possibly secrets) are folded
  # in, and only this digest is written to `.hwaro_cache.json`. `values`
  # memoizes per-key reads within one build (the digest is taken twice).
  # Stamp entries in `keys` are the previous build's (see above); they feed
  # the fast path and are not themselves digested.
  private def render_inputs_digest(globals : String, keys : Array(String), values : Hash(String, String)) : String
    stamps = previous_render_input_stamps(keys)
    digest = Digest::SHA256.new
    Utils::DigestUtils.update_length_prefixed(digest, globals)
    keys.each do |key|
      next if key.starts_with?(RENDER_INPUT_STAMP_PREFIX)
      Utils::DigestUtils.update_length_prefixed(digest, key)
      value = values[key] ||= render_read_value(key, stamps, values)
      Utils::DigestUtils.update_length_prefixed(digest, value)
    end
    digest.hexfinal
  end

  # The keys to persist: the real read keys plus a fresh stamp for every
  # file among them that exists (computed by `render_inputs_digest`).
  private def stamped_render_input_keys(keys : Array(String), values : Hash(String, String)) : Array(String)
    real = keys.reject(&.starts_with?(RENDER_INPUT_STAMP_PREFIX))
    stamps = real.compact_map do |key|
      next unless key.starts_with?(Content::Processors::TemplateEngine::FILE_READ_PREFIX)
      values[RENDER_INPUT_STAMP_MEMO + key[Content::Processors::TemplateEngine::FILE_READ_PREFIX.size..]]?
    end
    (real + stamps).sort!
  end

  # path => {mtime_ms, size, md5} from the stamp entries among `keys`.
  private def previous_render_input_stamps(keys : Array(String)) : Hash(String, {Int64, Int64, String})
    stamps = {} of String => {Int64, Int64, String}
    keys.each do |key|
      next unless key.starts_with?(RENDER_INPUT_STAMP_PREFIX)
      parts = key[RENDER_INPUT_STAMP_PREFIX.size..].split(':', 4)
      next unless parts.size == 4
      mtime = parts[0].to_i64?
      size = parts[1].to_i64?
      next unless mtime && size
      stamps[parts[3]] = {mtime, size, parts[2]}
    end
    stamps
  end

  # The current value behind one recorded read: the env value (set vs unset
  # kept distinct — `env("X")` renders differently for each), or a content
  # digest of the file (from its stamp when mtime and size are unchanged).
  private def render_read_value(key : String, stamps : Hash(String, {Int64, Int64, String}), values : Hash(String, String)) : String
    if key.starts_with?(Content::Processors::TemplateEngine::ENV_READ_PREFIX)
      name = key[Content::Processors::TemplateEngine::ENV_READ_PREFIX.size..]
      (value = ENV[name]?) ? "=#{value}" : "<unset>"
    elsif key.starts_with?(Content::Processors::TemplateEngine::FILE_READ_PREFIX)
      path = key[Content::Processors::TemplateEngine::FILE_READ_PREFIX.size..]
      begin
        info = File.info?(path)
        return "<absent>" unless info && info.file?
        mtime = info.modification_time.to_unix_ms
        size = info.size.to_i64
        stamp = stamps[path]?
        md5 = if stamp && stamp[0] == mtime && stamp[1] == size
                stamp[2]
              else
                Digest::MD5.new.file(path).hexfinal
              end
        values[RENDER_INPUT_STAMP_MEMO + path] = "#{RENDER_INPUT_STAMP_PREFIX}#{mtime}:#{size}:#{md5}:#{path}"
        md5
      rescue File::Error | IO::Error
        "<unreadable>"
      end
    elsif key.starts_with?(Content::Processors::TemplateEngine::ASSET_READ_PREFIX)
      name = key[Content::Processors::TemplateEngine::ASSET_READ_PREFIX.size..]
      Content::Hooks::AssetHooks.integrity(name, record: false) || "<absent>"
    else
      ""
    end
  end
end
