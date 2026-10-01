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
#     `[auto_includes]` / local-highlight tags with their `?v=` digest;
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
    Utils::DigestUtils.update_length_prefixed(digest, config.auto_includes.all_tags(config.base_url, cache_bust))
    digest.hexfinal
  end

  # One digest over the globals and the current value of every read in
  # `keys`. SHA-256 rather than MD5: env values (possibly secrets) are folded
  # in, and only this digest is written to `.hwaro_cache.json`. `values`
  # memoizes per-key reads within one build (the digest is taken twice).
  private def render_inputs_digest(globals : String, keys : Array(String), values : Hash(String, String)) : String
    digest = Digest::SHA256.new
    Utils::DigestUtils.update_length_prefixed(digest, globals)
    keys.each do |key|
      Utils::DigestUtils.update_length_prefixed(digest, key)
      value = values[key] ||= render_read_value(key)
      Utils::DigestUtils.update_length_prefixed(digest, value)
    end
    digest.hexfinal
  end

  # The current value behind one recorded read: the env value (set vs unset
  # kept distinct — `env("X")` renders differently for each), or a content
  # digest of the file.
  private def render_read_value(key : String) : String
    if key.starts_with?(Content::Processors::TemplateEngine::ENV_READ_PREFIX)
      name = key[Content::Processors::TemplateEngine::ENV_READ_PREFIX.size..]
      (value = ENV[name]?) ? "=#{value}" : "<unset>"
    elsif key.starts_with?(Content::Processors::TemplateEngine::FILE_READ_PREFIX)
      path = key[Content::Processors::TemplateEngine::FILE_READ_PREFIX.size..]
      begin
        File.file?(path) ? Digest::MD5.new.file(path).hexfinal : "<absent>"
      rescue File::Error | IO::Error
        "<unreadable>"
      end
    else
      ""
    end
  end
end
