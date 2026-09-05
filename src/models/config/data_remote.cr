# Config section — [[data.remote]].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # One `[[data.remote]]` entry — a declarative remote data source fetched
    # once per build (before render) into `site.data.<key>`. This class is
    # the validated config shape; fetching, caching and error handling live
    # in `Core::Build::RemoteData`. See docs/content/templates/data-model.md.
    class RemoteDataConfig
      # Accepted `format` values (also the set inference can produce).
      VALID_FORMATS = %w[json toml yaml csv]
      # Accepted `on_error` modes.
      VALID_ON_ERROR = %w[fail warn-and-use-cache warn-and-skip]

      # Template-facing name: the payload lands at `site.data.<key>`. Also
      # used as the cache filename, hence the restricted character set.
      property key : String
      # Absolute http(s) URL, already env-substituted.
      property url : String
      # Explicit payload format; nil = infer from the response Content-Type,
      # then from the URL's path extension, at fetch time.
      property format : String?
      # Extra request headers (values already env-substituted). Treated as
      # credentials: never logged, and dropped on cross-origin redirects.
      property headers : Hash(String, String)
      # Disk-cache TTL; nil = refetch on every build. The cache file is
      # written either way so `on_error = "warn-and-use-cache"` always has a
      # fallback once one fetch has succeeded.
      property cache_ttl : Time::Span?
      # "fail" | "warn-and-use-cache" | "warn-and-skip"
      property on_error : String

      def initialize(@key : String, @url : String)
        @format = nil
        @headers = {} of String => String
        @cache_ttl = nil
        @on_error = "fail"
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      # `[[data.remote]]` — declarative remote data sources. SHAPE is
      # validated strictly here (every bad entry raises HWARO_E_CONFIG)
      # because a mistake otherwise surfaces as a network failure at build
      # time, far from the config line that caused it.
      #
      # What is deliberately NOT validated here is whether an interpolated
      # `${VAR}` resolved. Interpolation already ran file-wide before TOML
      # parsing (see `load`), so an unset variable leaves the literal `${VAR}`
      # text in the value — but raising on it at config-load time made every
      # command that merely READS the config (`hwaro deploy`, `hwaro new`,
      # `hwaro tool ...`, and serve's `[build]` merge) abort on a remote
      # source it would never fetch. `RemoteData.load` raises the identical
      # HWARO_E_CONFIG when the entry is actually used instead.
      private def self.load_data_remote(config : Config)
        return unless data_section = config.raw["data"]?.try(&.as_h?)

        data_section.each_key do |key|
          next if key == "remote"
          Logger.warn "Unknown key 'data.#{key}' in config.toml — hwaro does not read it."
        end

        return unless remote_any = data_section["remote"]?
        # A `[data.remote]` single table (or any other shape) would otherwise
        # be ignored silently — the feature would just not run.
        remote_list = remote_any.as_a? ||
                      raise remote_config_error("'data.remote' must be an array of tables — declare each source with [[data.remote]] (double brackets).")

        seen_keys = Set(String).new
        config.data_remote = remote_list.map_with_index do |entry_any, index|
          where = "[[data.remote]] entry #{index + 1}"
          entry_hash = entry_any.as_h? ||
                       raise remote_config_error("#{where} must be a table ([[data.remote]] with key/url fields).")

          key = entry_hash["key"]?.try(&.as_s?) ||
                raise remote_config_error("#{where} is missing the required string 'key' (it names site.data.<key>).")
          where = "[[data.remote]] \"#{key}\""
          unless key.matches?(/\A[A-Za-z0-9_-]+\z/)
            raise remote_config_error("#{where}: key may contain only letters, digits, '_' and '-' (it becomes site.data.#{key} and a cache filename).")
          end
          # Compared case-insensitively: the key also names the cache files
          # under .hwaro/remote_data/, so "Team" and "team" are two config
          # entries but ONE pair of files on a case-insensitive filesystem
          # (macOS APFS, Windows) — they would overwrite each other's payload
          # and meta on every build, permanently defeating the TTL and the
          # offline `warn-and-use-cache` fallback for whichever lost.
          unless seen_keys.add?(key.downcase)
            raise remote_config_error("Duplicate [[data.remote]] key \"#{key}\" — each key may be declared only once, and keys are compared case-insensitively because they name cache files under .hwaro/remote_data/, which collide on case-insensitive filesystems (macOS, Windows).")
          end

          url = entry_hash["url"]?.try(&.as_s?) ||
                raise remote_config_error("#{where} is missing the required string 'url'.")
          validate_remote_url!(url, where)

          entry = RemoteDataConfig.new(key, url)

          if format_any = entry_hash["format"]?
            format = format_any.as_s? || raise remote_config_error("#{where}: 'format' must be a string.")
            format = "yaml" if format == "yml"
            unless RemoteDataConfig::VALID_FORMATS.includes?(format)
              raise remote_config_error("#{where}: unknown format \"#{format}\" — expected one of: #{RemoteDataConfig::VALID_FORMATS.join(", ")}.")
            end
            entry.format = format
          end

          if headers_any = entry_hash["headers"]?
            headers_hash = headers_any.as_h? ||
                           raise remote_config_error("#{where}: 'headers' must be a table of string values.")
            headers_hash.each do |name, value_any|
              value = value_any.as_s? ||
                      raise remote_config_error("#{where}: header \"#{name}\" must be a string.")
              entry.headers[name] = value
            end
          end

          if cache_any = entry_hash["cache"]?
            spec = cache_any.as_s? ||
                   raise remote_config_error("#{where}: 'cache' must be a duration string such as \"30m\" or \"1h\".")
            entry.cache_ttl = parse_cache_duration(spec) ||
                              raise remote_config_error("#{where}: invalid cache duration \"#{spec}\" — use <number><unit> with units s/m/h/d (e.g. \"90s\", \"30m\", \"1h\", \"7d\").")
          end

          if on_error_any = entry_hash["on_error"]?
            on_error = on_error_any.as_s?
            unless on_error && RemoteDataConfig::VALID_ON_ERROR.includes?(on_error)
              raise remote_config_error("#{where}: unknown on_error \"#{on_error_any.raw}\" — expected one of: #{RemoteDataConfig::VALID_ON_ERROR.join(", ")}.")
            end
            entry.on_error = on_error
          end

          entry_hash.each_key do |k|
            next if {"key", "url", "format", "headers", "cache", "on_error"}.includes?(k)
            Logger.warn "#{where}: unknown key '#{k}' — hwaro does not read it."
          end

          entry
        end
      end

      # Remote sources are http(s)-only, rejected here at config load; the
      # fetcher re-validates every redirect hop against the same rule.
      #
      # A url still carrying an unresolved `${VAR}` parses fine here (the
      # placeholder lands in the host or the path) and is left alone —
      # `RemoteData.load` names the variable when the entry is used.
      private def self.validate_remote_url!(url : String, where : String) : Nil
        uri = begin
          URI.parse(url)
        rescue URI::Error
          raise remote_config_error("#{where}: invalid url — expected an absolute http(s) URL.")
        end
        scheme = uri.scheme.try(&.downcase)
        host = uri.host
        return if {"http", "https"}.includes?(scheme) && host && !host.empty?
        raise remote_config_error("#{where}: url must be absolute http:// or https:// (got #{url.inspect}).")
      end

      # "90s" / "30m" / "1h" / "7d", or combinations ("1h30m"). Returns nil
      # on anything else — the caller owns the error message. Each component
      # is capped so an absurd magnitude can't overflow Time::Span.
      private def self.parse_cache_duration(spec : String) : Time::Span?
        return unless spec.matches?(/\A(?:\d+[smhd])+\z/)
        total = Time::Span.zero
        spec.scan(/(\d+)([smhd])/) do |m|
          amount = m[1].to_i64?
          return unless amount && amount <= 10_000_000
          total += case m[2]
                   when "s" then amount.seconds
                   when "m" then amount.minutes
                   when "h" then amount.hours
                   else          amount.days
                   end
        end
        total
      end

      private def self.remote_config_error(message : String) : Hwaro::HwaroError
        Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: message,
          hint: "Each [[data.remote]] entry needs key + url (http/https); optional: format (json|toml|yaml|csv), headers (table), cache (duration such as \"1h\"), on_error (fail|warn-and-use-cache|warn-and-skip).",
        )
      end
    end
  end
end
