# Build cache for tracking file changes and avoiding unnecessary rebuilds
#
# Uses file modification times, content checksums, and dependency checksums
# (templates, config) to detect changes. The cache is stored in a JSON file
# for persistence across builds.

require "digest/md5"
require "json"
require "../../utils/logger"
require "../../models/config"

module Hwaro
  module Core
    module Build
      # Represents a cached entry for a file
      struct CacheEntry
        include JSON::Serializable

        property path : String
        property mtime : Int64
        property hash : String
        property output_path : String
        @[JSON::Field(key: "template_hash", emit_null: false)]
        property template_hash : String

        @[JSON::Field(key: "config_hash", emit_null: false)]
        property config_hash : String

        # Fingerprint of the merged section [cascade] values that applied to
        # this page when it was built. A parent _index.md cascade edit changes
        # the fingerprint and invalidates the page even though its own source
        # file is untouched.
        @[JSON::Field(key: "cascade_hash", emit_null: false)]
        property cascade_hash : String

        def initialize(
          @path : String,
          @mtime : Int64,
          @hash : String,
          @output_path : String,
          @template_hash : String = "",
          @config_hash : String = "",
          @cascade_hash : String = "",
        )
        end

        # Allow missing fields when deserializing legacy entries
        def self.new(pull : JSON::PullParser)
          path = ""
          mtime = 0_i64
          hash = ""
          output_path = ""
          template_hash = ""
          config_hash = ""
          cascade_hash = ""

          pull.read_object do |key|
            case key
            when "path"          then path = pull.read_string
            when "mtime"         then mtime = pull.read_int.to_i64
            when "hash"          then hash = pull.read_string
            when "output_path"   then output_path = pull.read_string
            when "template_hash" then template_hash = pull.read_string
            when "config_hash"   then config_hash = pull.read_string
            when "cascade_hash"  then cascade_hash = pull.read_string
            else                      pull.skip
            end
          end

          new(path: path, mtime: mtime, hash: hash, output_path: output_path,
            template_hash: template_hash, config_hash: config_hash, cascade_hash: cascade_hash)
        end
      end

      # Persistent build metadata stored alongside per-file entries
      struct CacheMetadata
        include JSON::Serializable

        property template_hash : String
        property config_hash : String

        # Fingerprints of the global page/section sets. Listing pages (homepage,
        # section indexes, archives, taxonomy widgets) render content derived
        # from these sets even when their own source is unchanged, so a change
        # here forces those pages to re-render on an incremental build. Default
        # "" so older cache files (without these keys) load and rebuild once.
        @[JSON::Field(key: "page_set_hash", emit_null: false)]
        property page_set_hash : String = ""
        @[JSON::Field(key: "section_set_hash", emit_null: false)]
        property section_set_hash : String = ""

        def initialize(@template_hash : String = "", @config_hash : String = "",
                       @page_set_hash : String = "", @section_set_hash : String = "")
        end
      end

      # Top-level cache JSON structure
      struct CacheData
        include JSON::Serializable

        property metadata : CacheMetadata
        property entries : Array(CacheEntry)

        def initialize(@metadata : CacheMetadata, @entries : Array(CacheEntry))
        end
      end

      # Build cache manager for tracking file changes
      class Cache
        # Default cache filename - uses dot prefix to hide from directory listings
        # and 'hwaro_' prefix to identify it as project-specific cache
        CACHE_FILE = ".hwaro_cache.json"

        @entries : Hash(String, CacheEntry)
        @enabled : Bool
        @cache_path : String
        @metadata : CacheMetadata
        @mutex : Mutex

        # Current build's global checksums — set via set_global_checksums
        @current_template_hash : String = ""
        @current_config_hash : String = ""

        # True when in-memory state diverges from what's on disk, so #save
        # can skip rewriting the whole JSON on no-op warm builds. Set under
        # @mutex wherever entries or metadata actually change.
        @dirty : Bool = false

        def initialize(@enabled : Bool = true, @cache_path : String = CACHE_FILE)
          @entries = {} of String => CacheEntry
          @metadata = CacheMetadata.new
          @mutex = Mutex.new
          load if @enabled
        end

        # Set the current build's template and config checksums.
        # A config change always invalidates all entries. A template change
        # invalidates all entries only when `invalidate_on_template_change`
        # is true — with template dependency tracking active, the builder
        # passes false and per-page closure hashes (see `changed?`) decide
        # which pages a template edit actually affects.
        def set_global_checksums(template_hash : String, config_hash : String, invalidate_on_template_change : Bool = true)
          @current_template_hash = template_hash
          @current_config_hash = config_hash

          return unless @enabled

          invalidated = false

          if invalidate_on_template_change && !@metadata.template_hash.empty? && @metadata.template_hash != template_hash
            Logger.info "  Cache: templates changed — invalidating all entries."
            invalidated = true
          end

          if !@metadata.config_hash.empty? && @metadata.config_hash != config_hash
            Logger.info "  Cache: config changed — invalidating all entries."
            invalidated = true
          end

          if invalidated
            @mutex.synchronize { @entries.clear }
          end

          if invalidated || @metadata.template_hash != template_hash || @metadata.config_hash != config_hash
            @dirty = true
          end
          # Preserve the page/section-set fingerprints loaded from the prior
          # build so the render phase can compare against them before recording
          # the current ones.
          @metadata = CacheMetadata.new(template_hash: template_hash, config_hash: config_hash,
            page_set_hash: @metadata.page_set_hash, section_set_hash: @metadata.section_set_hash)
        end

        # Has the global page set (content page metadata that listings render —
        # path/url/title/date/weight/draft/section) changed since last build?
        def page_set_changed?(fingerprint : String) : Bool
          @metadata.page_set_hash != fingerprint
        end

        # Has the section set (section metadata that nav/menus render) changed?
        def section_set_changed?(fingerprint : String) : Bool
          @metadata.section_set_hash != fingerprint
        end

        # Record the current page/section-set fingerprints so the next build can
        # detect a change; marks the cache dirty when either value moves.
        def record_set_fingerprints(page_set : String, section_set : String) : Nil
          return unless @enabled
          if @metadata.page_set_hash != page_set || @metadata.section_set_hash != section_set
            @dirty = true
          end
          @metadata = CacheMetadata.new(template_hash: @metadata.template_hash, config_hash: @metadata.config_hash,
            page_set_hash: page_set, section_set_hash: section_set)
        end

        # Check if a file has changed since last build.
        # `template_hash` is the page's template closure fingerprint; nil
        # skips the comparison (non-page entries, or dependency tracking off).
        def changed?(file_path : String, output_path : String = "", cascade_hash : String = "", template_hash : String? = nil) : Bool
          return true unless @enabled
          return true unless File.exists?(file_path)

          entry = @mutex.synchronize { @entries[file_path]? }
          return true unless entry

          # Check if output exists
          if !output_path.empty? && !File.exists?(output_path)
            return true
          end

          # A parent section's [cascade] changed what this page inherits —
          # the source file is unchanged but the rendered output isn't.
          return true if entry.cascade_hash != cascade_hash

          # A template in this page's dependency closure changed.
          if template_hash && entry.template_hash != template_hash
            return true
          end

          # Fast path: check modification time first
          begin
            current_mtime = File.info(file_path).modification_time.to_unix_ms
            if current_mtime != entry.mtime
              # mtime changed — verify with content hash to catch false positives
              # (e.g. file touched but content identical)
              current_hash = compute_file_hash(file_path)
              return current_hash != entry.hash
            end
          rescue ex
            Logger.debug "Cache: failed to read mtime for #{file_path}: #{ex.message}"
            return true
          end

          false
        end

        # Check multiple files for changes (returns changed files)
        def filter_changed(files : Array(String)) : Array(String)
          return files unless @enabled
          files.select { |f| changed?(f) }
        end

        # Update cache entry for a file.
        # `template_hash` is the page's template closure fingerprint; nil
        # stores the global templates checksum (non-page entries).
        # Thread-safe: protected by mutex for concurrent parallel builds.
        def update(file_path : String, output_path : String = "", cascade_hash : String = "", template_hash : String? = nil)
          return unless @enabled
          return unless File.exists?(file_path)

          effective_template_hash = template_hash || @current_template_hash

          begin
            mtime = File.info(file_path).modification_time.to_unix_ms

            # Fast path: skip update if entry is unchanged (protected by mutex)
            @mutex.synchronize do
              existing = @entries[file_path]?
              if existing && existing.mtime == mtime && existing.output_path == output_path &&
                 existing.cascade_hash == cascade_hash && existing.template_hash == effective_template_hash
                return
              end
            end

            # Compute hash outside the lock to minimize contention
            content_hash = compute_file_hash(file_path)

            entry = CacheEntry.new(
              path: file_path,
              mtime: mtime,
              hash: content_hash,
              output_path: output_path,
              template_hash: effective_template_hash,
              config_hash: @current_config_hash,
              cascade_hash: cascade_hash,
            )

            @mutex.synchronize do
              # Re-check under lock: another fiber may have written a newer entry
              current = @entries[file_path]?
              if current.nil? || current.mtime <= mtime
                @entries[file_path] = entry
                @dirty = true
              end
            end
          rescue ex
            Logger.debug "Cache: failed to update entry for #{file_path}: #{ex.message}"
          end
        end

        # Remove entry from cache
        def invalidate(file_path : String)
          @mutex.synchronize do
            @dirty = true if @entries.delete(file_path)
          end
        end

        # Entries whose source file no longer exists on disk — i.e. a page that
        # was deleted or renamed since the prior build. Returns {source_path,
        # output_path} pairs so the caller can delete the orphaned output and
        # drop the dead entry. (The cache retains the prior build's
        # source→output map because unchanged pages are skipped, never updated.)
        def orphaned_outputs : Array(Tuple(String, String))
          @mutex.synchronize do
            @entries.compact_map do |path, entry|
              next if entry.output_path.empty?
              next if File.exists?(path)
              {path, entry.output_path}
            end
          end
        end

        # Clear all cache entries
        def clear
          @mutex.synchronize do
            @entries.clear
            @metadata = CacheMetadata.new
            @dirty = true
          end
          File.delete(@cache_path) if File.exists?(@cache_path)
        end

        # Save cache to disk using atomic write (temp file + rename)
        # to prevent corruption from partial writes (e.g. disk full, crash).
        # No-op when nothing changed since load — a warm all-hits build
        # otherwise re-serializes every entry just to write identical bytes.
        def save
          return unless @enabled
          return unless @dirty
          tmp_path = "#{@cache_path}.tmp"
          begin
            # Snapshot shared state under the mutex: parallel fibers may still
            # be writing @entries via #update, and iterating a Hash mid-mutation
            # is undefined behavior under -Dpreview_mt.
            data = @mutex.synchronize do
              CacheData.new(metadata: @metadata, entries: @entries.values)
            end
            File.write(tmp_path, data.to_json)
            File.rename(tmp_path, @cache_path)
            @dirty = false
          rescue ex
            Logger.warn "Cache: failed to save cache file: #{ex.message}"
            # Clean up temp file if rename failed
            File.delete(tmp_path) if File.exists?(tmp_path)
          end
        end

        # Load cache from disk
        def load
          return unless @enabled
          return unless File.exists?(@cache_path)

          begin
            content = File.read(@cache_path)
          rescue ex
            Logger.warn "Cache: failed to read cache file: #{ex.message}"
            delete_corrupt_cache
            return
          end

          return if content.empty?

          begin
            # Try loading new format with metadata
            data = CacheData.from_json(content)
            @metadata = data.metadata
            data.entries.each { |e| @entries[e.path] = e }
          rescue JSON::ParseException | JSON::SerializableError
            # Fall back to legacy format (plain array of entries); mark dirty
            # so the next save upgrades the file to the metadata format even
            # on an otherwise no-op build.
            begin
              entries = Array(CacheEntry).from_json(content)
              entries.each { |e| @entries[e.path] = e }
              @metadata = CacheMetadata.new
              @dirty = true
            rescue ex : JSON::ParseException | JSON::SerializableError
              Logger.warn "Cache: corrupt cache file, rebuilding from scratch: #{ex.message}"
              @entries.clear
              @metadata = CacheMetadata.new
              delete_corrupt_cache
            end
          end
        end

        # Remove corrupt cache file so the next build starts clean
        private def delete_corrupt_cache
          File.delete(@cache_path) if File.exists?(@cache_path)
        rescue ex : File::Error | IO::Error
          # Cache will be overwritten on save; log at debug for diagnostics
          Logger.debug "Cache: failed to delete corrupt cache file: #{ex.message}"
        end

        # Get cache statistics
        def stats : {total: Int32, valid: Int32}
          total = @entries.size
          valid = @entries.count { |_, e| File.exists?(e.path) }
          {total: total, valid: valid}
        end

        # Check if caching is enabled
        def enabled? : Bool
          @enabled
        end

        # Compute MD5 checksum of a file's content (streaming to avoid
        # loading large files entirely into memory)
        def compute_file_hash(file_path : String) : String
          digest = Digest::MD5.new
          buffer = Bytes.new(8192)
          File.open(file_path, "r") do |io|
            while (bytes_read = io.read(buffer)) > 0
              digest.update(buffer[0, bytes_read])
            end
          end
          digest.final.hexstring
        end

        # Compute a combined checksum for a set of template files
        def self.compute_templates_hash(templates : Hash(String, String)) : String
          digest = Digest::MD5.new
          templates.keys.sort!.each do |name|
            digest.update(name)
            digest.update(templates[name])
          end
          digest.final.hexstring
        end

        # Compute a checksum for the config file
        def self.compute_config_hash(config_path : String = "config.toml") : String
          if File.exists?(config_path)
            Digest::MD5.hexdigest(File.read(config_path))
          else
            ""
          end
        end

        # Compute a checksum for the *effective* (env-merged, env-substituted)
        # config plus the active env name and resolved base_url. Hashing the
        # parsed `config.raw` rather than the raw config.toml bytes means an
        # env override file (config.<env>.toml), changed ${ENV_VAR}
        # substitutions, or a --base-url override all invalidate the per-page
        # cache — none of which the file-bytes hash above can detect — while a
        # formatting-only edit to config.toml no longer forces a full rebuild.
        def self.compute_config_hash(config : Models::Config, env : String? = nil) : String
          digest = Digest::MD5.new
          digest.update(env || "")
          digest.update(config.base_url)
          config.raw.keys.sort!.each do |key|
            digest.update(key)
            digest.update(config.raw[key].to_s)
          end
          digest.final.hexstring
        end
      end
    end
  end
end
