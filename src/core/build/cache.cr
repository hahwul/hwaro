# Build cache for tracking file changes and avoiding unnecessary rebuilds
#
# Uses file modification times, content checksums, and dependency checksums
# (templates, config) to detect changes. The cache is stored in a JSON file
# for persistence across builds.

require "digest/md5"
require "json"
require "../../utils/logger"

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

        def initialize(
          @path : String,
          @mtime : Int64,
          @hash : String,
          @output_path : String,
          @template_hash : String = "",
          @config_hash : String = "",
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

          pull.read_object do |key|
            case key
            when "path"          then path = pull.read_string
            when "mtime"         then mtime = pull.read_int.to_i64
            when "hash"          then hash = pull.read_string
            when "output_path"   then output_path = pull.read_string
            when "template_hash" then template_hash = pull.read_string
            when "config_hash"   then config_hash = pull.read_string
            else                      pull.skip
            end
          end

          new(path: path, mtime: mtime, hash: hash, output_path: output_path,
            template_hash: template_hash, config_hash: config_hash)
        end
      end

      # Persistent build metadata stored alongside per-file entries
      struct CacheMetadata
        include JSON::Serializable

        property template_hash : String
        property config_hash : String

        def initialize(@template_hash : String = "", @config_hash : String = "")
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

        def initialize(@enabled : Bool = true, @cache_path : String = CACHE_FILE)
          @entries = {} of String => CacheEntry
          @metadata = CacheMetadata.new
          @mutex = Mutex.new
          load if @enabled
        end

        # Set the current build's template and config checksums.
        # If either differs from the previous build's metadata, all entries
        # are invalidated so every page is rebuilt.
        def set_global_checksums(template_hash : String, config_hash : String)
          @current_template_hash = template_hash
          @current_config_hash = config_hash

          return unless @enabled

          invalidated = false

          if !@metadata.template_hash.empty? && @metadata.template_hash != template_hash
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

          @metadata = CacheMetadata.new(template_hash: template_hash, config_hash: config_hash)
        end

        # Check if a file has changed since last build
        def changed?(file_path : String, output_path : String = "") : Bool
          return true unless @enabled
          return true unless File.exists?(file_path)

          entry = @mutex.synchronize { @entries[file_path]? }
          return true unless entry

          # Check if output exists
          if !output_path.empty? && !File.exists?(output_path)
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
        # Thread-safe: protected by mutex for concurrent parallel builds.
        def update(file_path : String, output_path : String = "")
          return unless @enabled
          return unless File.exists?(file_path)

          begin
            mtime = File.info(file_path).modification_time.to_unix_ms

            # Compute hash outside the lock to minimize contention
            existing = @entries[file_path]?
            if existing && existing.mtime == mtime && existing.output_path == output_path
              return
            end

            content_hash = compute_file_hash(file_path)

            entry = CacheEntry.new(
              path: file_path,
              mtime: mtime,
              hash: content_hash,
              output_path: output_path,
              template_hash: @current_template_hash,
              config_hash: @current_config_hash,
            )

            @mutex.synchronize do
              @entries[file_path] = entry
            end
          rescue ex
            Logger.debug "Cache: failed to update entry for #{file_path}: #{ex.message}"
          end
        end

        # Remove entry from cache
        def invalidate(file_path : String)
          @mutex.synchronize do
            @entries.delete(file_path)
          end
        end

        # Clear all cache entries
        def clear
          @entries.clear
          @metadata = CacheMetadata.new
          File.delete(@cache_path) if File.exists?(@cache_path)
        end

        # Save cache to disk
        def save
          return unless @enabled
          begin
            data = CacheData.new(metadata: @metadata, entries: @entries.values)
            File.write(@cache_path, data.to_json)
          rescue ex
            Logger.warn "Cache: failed to save cache file: #{ex.message}"
          end
        end

        # Load cache from disk
        def load
          return unless @enabled
          return unless File.exists?(@cache_path)

          content = File.read(@cache_path)
          begin
            # Try loading new format with metadata
            data = CacheData.from_json(content)
            @metadata = data.metadata
            data.entries.each { |e| @entries[e.path] = e }
          rescue
            # Fall back to legacy format (plain array of entries)
            begin
              entries = Array(CacheEntry).from_json(content)
              entries.each { |e| @entries[e.path] = e }
              @metadata = CacheMetadata.new
            rescue ex
              Logger.debug "Cache: failed to load cache file, starting fresh: #{ex.message}"
              @entries.clear
              @metadata = CacheMetadata.new
            end
          end
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
          templates.keys.sort.each do |name|
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
      end
    end
  end
end
