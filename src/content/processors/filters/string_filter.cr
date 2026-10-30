require "base64"
require "crinja"
require "openssl"
require "../../../utils/crinja_utils"

module Hwaro
  module Content
    module Processors
      module Filters
        module StringFilters
          # Hash filters and the OpenSSL digest each one computes.
          DIGESTS = {"md5" => "MD5", "sha1" => "SHA1", "sha256" => "SHA256", "sha384" => "SHA384", "sha512" => "SHA512"}

          REGEX_CACHE_SIZE = 256
          @@regex_cache = {} of String => Regex
          @@regex_mutex = Mutex.new

          # `pattern` compiled once per process, shared by every render
          # worker (a compiled Regex is read-only; PCRE2 match data is
          # per-thread). Bounded: the oldest pattern is evicted first.
          # Raises ArgumentError for an invalid pattern.
          def self.regex(pattern : String) : Regex
            @@regex_mutex.synchronize do
              @@regex_cache[pattern]? || begin
                @@regex_cache.delete(@@regex_cache.first_key) if @@regex_cache.size >= REGEX_CACHE_SIZE
                @@regex_cache[pattern] = Regex.new(pattern)
              end
            end
          end

          # Expands a Zola (Rust regex) replacement string for one match:
          # `$1` / `${1}` by index, `$name` / `${name}` by name, `$$` for a
          # literal `$`. As in Rust, `$name` takes the longest run of
          # `[0-9A-Za-z_]` (`$1a` names group "1a"), an unknown or unmatched
          # group expands to nothing, a `$` not followed by a name stays
          # literal, and backslashes have no special meaning.
          def self.expand_replacement(rep : String, match : Regex::MatchData) : String
            return rep unless rep.includes?('$')
            String.build do |io|
              i = 0
              size = rep.bytesize
              while i < size
                byte = rep.byte_at(i)
                unless byte === '$' && i + 1 < size
                  io.write_byte(byte)
                  i += 1
                  next
                end
                following = rep.byte_at(i + 1)
                if following === '$'
                  io << '$'
                  i += 2
                elsif following === '{'
                  close = rep.byte_index('}', i + 2)
                  if close && close > i + 2
                    io << capture(match, rep.byte_slice(i + 2, close - i - 2))
                    i = close + 1
                  else
                    io << '$'
                    i += 1
                  end
                else
                  stop = i + 1
                  while stop < size && ((b = rep.byte_at(stop)).unsafe_chr.ascii_alphanumeric? || b === '_')
                    stop += 1
                  end
                  if stop == i + 1
                    io << '$'
                    i += 1
                  else
                    io << capture(match, rep.byte_slice(i + 1, stop - i - 1))
                    i = stop
                  end
                end
              end
            end
          end

          private def self.capture(match : Regex::MatchData, name : String) : String
            if name.each_char.all?(&.ascii_number?)
              index = name.to_i?
              (index && index < match.size ? match[index]? : nil) || ""
            else
              match[name]? || ""
            end
          end

          def self.register(env : Crinja)
            # `regex_replace(pattern=, rep=)` — Zola's filter (Hugo's
            # `replaceRE`): every match of the PCRE2 `pattern` is replaced
            # by `rep`, expanded as in `expand_replacement`.
            env.filters["regex_replace"] = Crinja.filter({pattern: nil, rep: ""}) do
              pattern = arguments["pattern"]
              raise Crinja::RuntimeError.new("regex_replace requires a pattern") if pattern.none? || pattern.undefined?
              pattern = pattern.to_s
              rep = arguments["rep"].to_s
              text = target.to_s
              # PCRE2 refuses to match invalid UTF-8 (ArgumentError).
              text = text.scrub unless text.valid_encoding?
              regex = begin
                StringFilters.regex(pattern)
              rescue ex : ArgumentError
                raise Crinja::RuntimeError.new("regex_replace: invalid pattern #{pattern.inspect}: #{ex.message}")
              end
              begin
                text.gsub(regex) { |_, match| StringFilters.expand_replacement(rep, match) }
              rescue ex : Regex::Error
                raise Crinja::RuntimeError.new("regex_replace: #{ex.message} for pattern #{pattern.inspect}")
              end
            end

            env.filters["base64_encode"] = Crinja.filter do
              Base64.strict_encode(target.to_s)
            end

            # Accepts the standard and URL-safe alphabets, with or without
            # padding. The decoded bytes must be UTF-8 text: a template
            # string cannot carry arbitrary binary.
            env.filters["base64_decode"] = Crinja.filter do
              decoded = begin
                Base64.decode_string(target.to_s)
              rescue ex : Base64::Error
                raise Crinja::RuntimeError.new("base64_decode: invalid base64 input: #{ex.message}")
              end
              raise Crinja::RuntimeError.new("base64_decode: decoded bytes are not valid UTF-8") unless decoded.valid_encoding?
              decoded
            end

            # `md5`, `sha1`, `sha256`, `sha384`, `sha512` — lowercase hex of
            # the digest of the string's UTF-8 bytes; `base64=true` returns
            # the digest in base64 instead (an SRI value is
            # `"sha384-" ~ (text | sha384(base64=true))`).
            DIGESTS.each do |name, algorithm|
              env.filters[name] = Crinja.filter({base64: false}) do
                digest = OpenSSL::Digest.new(algorithm).update(target.to_s).final
                arguments["base64"].truthy? ? Base64.strict_encode(digest) : digest.hexstring
              end
            end

            # Truncate words filter
            env.filters["truncate_words"] = Crinja.filter({length: 50, end: "..."}) do
              # Strip first: a leading-whitespace input would otherwise split into
              # a leading "" token, consuming a word slot and emitting a stray
              # leading space (off-by-one truncation).
              text = target.to_s.strip
              # Lenient coercion: a quoted `length="20"` (which is all a
              # shortcode can forward) used to fall into the `rescue` and
              # silently mean 50, and a negative count sliced `words[0...-n]`
              # and dropped words off the END of the text.
              # `max:` leaves one unit of headroom for the `+ 1` below. to_count
              # saturates out-of-range input at `max` instead of raising, so a
              # `length=2147483647` (or anything larger, which clamps to the
              # same value) landed on Int32::MAX and made `length + 1` raise
              # OverflowError — aborting the render of the whole page, where
              # the intended behaviour for an over-large length is "return the
              # text untouched".
              length = Utils::CrinjaUtils.to_count(arguments["length"], default: 50, max: Int32::MAX - 1)
              ending = arguments["end"].to_s

              # Split one past the limit so `words.size > length` can tell
              # "exactly length words" from "more than length words".
              words = text.split(/\s+/, limit: length + 1)
              if words.size > length
                words[0...length].join(" ") + ending
              else
                text
              end
            end

            # Slugify filter (delegates to TextUtils for CJK support)
            env.filters["slugify"] = Crinja.filter do
              Utils::TextUtils.slugify(target.to_s)
            end

            # Split filter
            env.filters["split"] = Crinja.filter({pat: ","}) do
              text = target.to_s
              separator = arguments["pat"].to_s
              parts = text.split(separator).map { |s| Crinja::Value.new(s.strip) }
              Crinja::Value.new(parts)
            end

            # Trim filter
            env.filters["trim"] = Crinja.filter do
              target.to_s.strip
            end
          end
        end
      end
    end
  end
end
