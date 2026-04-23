# Stable error taxonomy for Hwaro.
#
# Provides a small enum of error codes and categories so that scripts,
# CI pipelines, and agents can reliably branch on *what kind of failure*
# occurred instead of parsing human-readable messages. Each code also
# maps to a stable process exit code.
#
# Only the highest-traffic error sites are classified today. Other
# failure paths continue to surface as plain `Exception`s and keep the
# legacy exit code (1) / text format (`Error: <message>`). Classified
# errors get the prefixed text form (`Error [HWARO_E_USAGE]: <message>`)
# and, under `--json` or `Logger.quiet?`, the structured JSON payload
# `{"status":"error","error":{"code":"…","category":"…","message":"…","hint":"…"}}`.
#
# See `docs/content/start/cli.md` for the user-facing reference table.

module Hwaro
  module Errors
    # Exit code mapping (see docs/content/start/cli.md). Kept in one place
    # so `bin/hwaro` process-exit codes stay consistent across call sites.
    EXIT_SUCCESS  =  0
    EXIT_GENERIC  =  1 # legacy/default failure
    EXIT_USAGE    =  2
    EXIT_CONFIG   =  3
    EXIT_TEMPLATE =  4
    EXIT_CONTENT  =  5
    EXIT_IO       =  6
    EXIT_NETWORK  =  7
    EXIT_INTERNAL = 70

    # Error code identifiers — kept as stable strings that surface in
    # user-facing output (text prefix and JSON `code` field). Changing
    # these is a breaking change for downstream consumers.
    HWARO_E_USAGE    = "HWARO_E_USAGE"
    HWARO_E_CONFIG   = "HWARO_E_CONFIG"
    HWARO_E_TEMPLATE = "HWARO_E_TEMPLATE"
    HWARO_E_CONTENT  = "HWARO_E_CONTENT"
    HWARO_E_IO       = "HWARO_E_IO"
    HWARO_E_NETWORK  = "HWARO_E_NETWORK"
    HWARO_E_INTERNAL = "HWARO_E_INTERNAL"

    # Canonical category for each code. Categories are short symbol-like
    # strings agents can group/filter on without stringly matching every
    # individual code.
    CATEGORY_FOR = {
      HWARO_E_USAGE    => :usage,
      HWARO_E_CONFIG   => :config,
      HWARO_E_TEMPLATE => :template,
      HWARO_E_CONTENT  => :content,
      HWARO_E_IO       => :io,
      HWARO_E_NETWORK  => :network,
      HWARO_E_INTERNAL => :internal,
    } of String => Symbol

    # Exit code per error code.
    EXIT_FOR = {
      HWARO_E_USAGE    => EXIT_USAGE,
      HWARO_E_CONFIG   => EXIT_CONFIG,
      HWARO_E_TEMPLATE => EXIT_TEMPLATE,
      HWARO_E_CONTENT  => EXIT_CONTENT,
      HWARO_E_IO       => EXIT_IO,
      HWARO_E_NETWORK  => EXIT_NETWORK,
      HWARO_E_INTERNAL => EXIT_INTERNAL,
    } of String => Int32

    def self.category_for(code : String) : Symbol
      CATEGORY_FOR[code]? || :internal
    end

    def self.exit_for(code : String) : Int32
      EXIT_FOR[code]? || EXIT_GENERIC
    end
  end

  # Exception carrying a classified error code, category and optional hint.
  # Callers raise this from high-value paths; the Runner (and a handful of
  # JSON-emitting command sites) pick it up and render the structured form.
  class HwaroError < Exception
    getter code : String
    getter category : Symbol
    getter hint : String?

    def initialize(code : String, message : String, hint : String? = nil, cause : Exception? = nil)
      super(message, cause)
      @code = code
      @category = Errors.category_for(code)
      @hint = hint
    end

    def exit_code : Int32
      Errors.exit_for(@code)
    end

    # Structured payload used by --json / quiet-mode emission sites.
    def to_error_payload
      payload = {
        "status" => "error",
        "error"  => {
          "code"     => @code,
          "category" => @category.to_s,
          "message"  => message || "",
          "hint"     => @hint,
        },
      }
      payload
    end
  end
end
