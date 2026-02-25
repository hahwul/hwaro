# Build cache for tracking file changes and avoiding unnecessary rebuilds
#
# Uses file modification times and content hashes to detect changes.
# The cache is stored in a JSON file for persistence across builds.

require "json"
require "digest/md5"
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

        def initialize(@path : String, @mtime : Int64, @hash : String, @output_path : String)
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

        def initialize(@enabled : Bool = true, @cache_path : String = CACHE_FILE)
          @entries = {} of String => CacheEntry
          load if @enabled
        end

        # Check if a file has changed since last build
        def changed?(file_path : String, output_path : String = "") : Bool
          return true unless @enabled
          return true unless File.exists?(file_path)

          entry = @entries[file_path]?
          return true unless entry

          # Check if output exists
          if !output_path.empty? && !File.exists?(output_path)
            return true
          end

          # Check modification time (fast and sufficient check)
          # mtime match is reliable enough — skip expensive MD5 re-read.
          # Uses millisecond precision to detect sub-second changes.
          begin
            current_mtime = File.info(file_path).modification_time.to_unix_ms
            return current_mtime != entry.mtime
          rescue
            return true
          end
        end

        # Check multiple files for changes (returns changed files)
        def filter_changed(files : Array(String)) : Array(String)
          return files unless @enabled
          files.select { |f| changed?(f) }
        end

        # Update cache entry for a file
        # Uses mtime as the sole change indicator. Hash computation is skipped
        # on the hot path since changed? only compares mtime, making the
        # expensive File.read + MD5 unnecessary during normal builds.
        def update(file_path : String, output_path : String = "")
          return unless @enabled
          return unless File.exists?(file_path)

          begin
            mtime = File.info(file_path).modification_time.to_unix_ms

            # Reuse existing entry if mtime hasn't changed
            existing = @entries[file_path]?
            if existing && existing.mtime == mtime && existing.output_path == output_path
              return
            end

            @entries[file_path] = CacheEntry.new(
              path: file_path,
              mtime: mtime,
              hash: "",
              output_path: output_path
            )
          rescue ex
            # Ignore errors for individual files
          end
        end

        # Remove entry from cache
        def invalidate(file_path : String)
          @entries.delete(file_path)
        end

        # Clear all cache entries
        def clear
          @entries.clear
          File.delete(@cache_path) if File.exists?(@cache_path)
        end

        # Save cache to disk
        def save
          return unless @enabled
          begin
            File.write(@cache_path, @entries.values.to_json)
          rescue ex
            # Silently ignore save errors
          end
        end

        # Load cache from disk
        def load
          return unless @enabled
          return unless File.exists?(@cache_path)

          begin
            content = File.read(@cache_path)
            entries = Array(CacheEntry).from_json(content)
            entries.each { |e| @entries[e.path] = e }
          rescue ex
            # Start fresh if cache is corrupted
            @entries.clear
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

        private def compute_hash(file_path : String) : String
          content = File.read(file_path)
          Digest::MD5.hexdigest(content)
        rescue
          ""
        end
      end
    end
  end
end
