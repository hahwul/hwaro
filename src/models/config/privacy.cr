# Config section — [privacy].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # `[privacy]` — download third-party assets at build time and serve them
    # from the site itself. Fetching, caching and rewriting live in
    # `Core::Build::Privacy`. See docs/content/features/privacy.md.
    class PrivacyConfig
      VALID_ON_ERROR = %w[warn-and-keep fail]

      property enabled : Bool = false
      # Hosts to localize; empty = every external host.
      property include : Array(String) = [] of String
      # Hosts never localized; wins over `include`.
      property exclude : Array(String) = [] of String
      # Directory under the build output that holds the downloaded files.
      property output_dir : String = "assets/external"
      # How long a downloaded file is reused without asking the network.
      property cache_ttl : Time::Span = 7.days
      # "warn-and-keep" (leave the external URL) | "fail"
      property on_error : String = "warn-and-keep"
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_privacy(config : Config)
        return unless s = config.raw["privacy"]?.try(&.as_h?)
        privacy = config.privacy

        privacy.enabled = bool_value(s["enabled"]?, privacy.enabled)
        string_list?(s["include"]?, "[privacy] include").try { |hosts| privacy.include = hosts.map(&.strip.downcase) }
        string_list?(s["exclude"]?, "[privacy] exclude").try { |hosts| privacy.exclude = hosts.map(&.strip.downcase) }

        if dir = s["output_dir"]?.try(&.as_s?)
          dir = dir.strip("/")
          privacy.output_dir = dir unless dir.empty?
        end

        if ttl = s["cache_ttl"]?
          spec = ttl.as_s? || raise privacy_config_error("[privacy] cache_ttl must be a duration string such as \"7d\" or \"12h\".")
          privacy.cache_ttl = parse_cache_duration(spec) ||
                              raise privacy_config_error("[privacy] invalid cache_ttl \"#{spec}\" — use <number><unit> with units s/m/h/d (e.g. \"12h\", \"7d\").")
        end

        if on_error_any = s["on_error"]?
          on_error = on_error_any.as_s?
          unless on_error && PrivacyConfig::VALID_ON_ERROR.includes?(on_error)
            raise privacy_config_error("[privacy] unknown on_error \"#{on_error_any.raw}\" — expected one of: #{PrivacyConfig::VALID_ON_ERROR.join(", ")}.")
          end
          privacy.on_error = on_error
        end

        s.each_key do |key|
          next if key.in?("enabled", "include", "exclude", "output_dir", "cache_ttl", "on_error")
          Logger.warn "[privacy]: unknown key '#{key}' — hwaro does not read it."
        end
      end

      private def self.privacy_config_error(message : String) : Hwaro::HwaroError
        Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: message,
          hint: "[privacy] keys: enabled, include/exclude (host lists), output_dir, cache_ttl (duration such as \"7d\"), on_error (warn-and-keep|fail).",
        )
      end
    end
  end
end
