# Config section — [csp].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # `[csp]` — a Content-Security-Policy built from each page's inline
    # script/style hashes. Hashing, policy assembly and emission live in
    # `Core::Build::Csp`. See docs/content/features/csp.md.
    class CspConfig
      VALID_MODES = %w[headers meta]

      # The policy used for anything `[csp.directives]` leaves unset.
      DEFAULT_DIRECTIVES = {
        "default-src"     => "'self'",
        "script-src"      => "'self'",
        "style-src"       => "'self'",
        "img-src"         => "'self' data:",
        "font-src"        => "'self'",
        "connect-src"     => "'self'",
        "object-src"      => "'none'",
        "base-uri"        => "'self'",
        "frame-ancestors" => "'self'",
      }

      property enabled : Bool = false
      # "headers" (a Netlify / Cloudflare Pages `_headers` file) | "meta"
      property mode : String = "headers"
      # Output-root-relative path of the headers file (headers mode).
      property headers_file : String = "_headers"
      property report_only : Bool = false
      # `[csp.directives]`, in config order. Merged over DEFAULT_DIRECTIVES
      # by `Core::Build::Csp`; an empty value removes a default directive
      # (or, for any other name, is a valueless one: upgrade-insecure-requests).
      property directives : Hash(String, String) = {} of String => String

      def meta? : Bool
        @mode == "meta"
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_csp(config : Config)
        return unless s = config.raw["csp"]?.try(&.as_h?)
        csp = config.csp

        csp.enabled = bool_value(s["enabled"]?, csp.enabled)
        csp.report_only = bool_value(s["report_only"]?, csp.report_only)

        if mode_any = s["mode"]?
          mode = mode_any.as_s?
          unless mode && CspConfig::VALID_MODES.includes?(mode)
            raise csp_config_error("[csp] unknown mode \"#{mode_any.raw}\" — expected one of: #{CspConfig::VALID_MODES.join(", ")}.")
          end
          csp.mode = mode
        end

        if file_any = s["headers_file"]?
          file = file_any.as_s?.try(&.strip.lchop('/'))
          raise csp_config_error("[csp] headers_file must be a non-empty path such as \"_headers\".") if file.nil? || file.empty?
          csp.headers_file = file
        end

        if directives_any = s["directives"]?
          table = directives_any.as_h? || raise csp_config_error("[csp] directives must be a table of directive = \"sources\" strings.")
          table.each do |name, value_any|
            value = value_any.as_s? || raise csp_config_error("[csp.directives] #{name} must be a string such as \"'self'\".")
            unless name.matches?(/\A[a-z][a-z-]*\z/)
              raise csp_config_error("[csp.directives] \"#{name}\" is not a directive name (lowercase letters and dashes, e.g. img-src).")
            end
            if value.includes?(';') || value.includes?(',')
              raise csp_config_error("[csp.directives] #{name} must not contain ';' or ',' — list sources separated by spaces.")
            end
            csp.directives[name] = value.split.join(" ")
          end
        end

        if csp.enabled && csp.report_only && csp.meta?
          raise csp_config_error("[csp] report_only cannot be used with mode = \"meta\": browsers ignore Content-Security-Policy-Report-Only in a <meta> tag.")
        end

        s.each_key do |key|
          next if key.in?("enabled", "mode", "headers_file", "report_only", "directives")
          Logger.warn "[csp]: unknown key '#{key}' — hwaro does not read it."
        end
      end

      private def self.csp_config_error(message : String) : Hwaro::HwaroError
        Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: message,
          hint: "[csp] keys: enabled, mode (headers|meta), headers_file, report_only, and a [csp.directives] table.",
        )
      end
    end
  end
end
