require "json"
require "../../utils/file_safe"
require "../../utils/hwaro_dir"

module Hwaro
  module Content
    module Hooks
      # What each generated image variant was cut from.
      #
      # Warm builds (`--cache`, every `serve` rebuild) reuse a variant that
      # already sits in the output directory. File mtimes alone cannot say
      # whether that is still right: a source swapped for an older-mtime copy
      # (`rsync -a`, `tar -x`, a restored revision) passes an "is the variant
      # newer than the source" test, and a change to the encode settings
      # (`quality`, the LQIP knobs) leaves every file looking fresh. So each
      # variant is stamped with a fingerprint of its inputs — the source's
      # exact mtime and size plus the encode settings — and is reused only
      # while the stamp equals the one the current build would produce. No
      # stamp (first build after an upgrade, `.hwaro/` deleted) means "not
      # proven fresh", so the variant is regenerated once; the bytes it
      # regenerates are the same a cold build writes.
      #
      # The record is an append-only JSON-lines log in `.hwaro/`, next to the
      # other workspace state and never published: recording is O(1) per
      # variant (render-time fill/crop variants are made one at a time), the
      # last line for a variant wins, and a log that has outgrown its live
      # entries is rewritten when it is loaded.
      module ImageVariantStamps
        extend self

        LOG_NAME = "image_variants.log"

        @@stamps = {} of String => Hash(String, String)
        @@mutex = Mutex.new

        # Fingerprint of `source` plus `settings`; nil when it cannot be
        # statted (nothing to reuse then).
        def fingerprint(source : String, settings : String) : String?
          info = File.info?(source)
          return unless info
          "#{info.modification_time.to_unix_ms}:#{info.size}:#{settings}"
        end

        # Was `dest` last written from exactly `fingerprint`?
        def fresh?(dest : String, fingerprint : String) : Bool
          @@mutex.synchronize { load[dest]? == fingerprint }
        end

        # Record that `dest` was just written from `fingerprint`.
        def record(dest : String, fingerprint : String) : Nil
          @@mutex.synchronize do
            stamps = load
            return if stamps[dest]? == fingerprint
            stamps[dest] = fingerprint
            append(dest, fingerprint)
          end
        end

        private def log_path : String
          File.expand_path(File.join(Utils::HwaroDir::DIR, LOG_NAME))
        end

        # The stamps behind the current project's log (cwd-relative, loaded
        # once per path). Caller holds @@mutex.
        private def load : Hash(String, String)
          path = log_path
          if loaded = @@stamps[path]?
            return loaded
          end
          entries = {} of String => String
          lines = 0
          begin
            if File.file?(path)
              File.each_line(path) do |line|
                lines += 1
                pair = begin
                  Array(String).from_json(line)
                rescue JSON::Error
                  next
                end
                entries[pair[0]] = pair[1] if pair.size == 2
              end
            end
          rescue IO::Error
            # unreadable log: start empty, everything regenerates once
          end
          compact(path, entries) if lines > entries.size * 2 + 256
          @@stamps[path] = entries
        end

        private def append(dest : String, fingerprint : String) : Nil
          path = log_path
          Utils::FileSafe.mkdir_p(File.dirname(path))
          Utils::HwaroDir.ensure_self_ignore(File.dirname(path))
          File.open(path, "a") { |io| io.puts [dest, fingerprint].to_json }
        rescue IO::Error
          nil # reuse just stays conservative: the next build regenerates
        end

        private def compact(path : String, entries : Hash(String, String)) : Nil
          Utils::FileSafe.atomic_write(path, entries.join('\n') { |dest, fp| [dest, fp].to_json } + "\n")
        rescue IO::Error
          nil
        end
      end
    end
  end
end
