# Doctor — Issue record and the CHECK_GROUPS registry every diagnostic joins.
#
# Split out of doctor.cr, which keeps the require order, the Doctor ivars
# and `run`. Parts only define or reopen types: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    # Represents a single diagnostic issue found by the doctor
    record Issue, id : String, level : Symbol, category : String, file : String?, message : String do
      include JSON::Serializable

      @[JSON::Field(converter: Hwaro::Services::Issue::SymbolConverter)]
      getter level : Symbol

      # Issue is JSON-serialized for `hwaro doctor --json`. We don't currently
      # consume that JSON back into Issue values, but the converter still needs
      # a correct `from_json` so a future round-trip (or third-party tooling
      # that reuses the schema) doesn't blow up. The previous implementation
      # returned `String` from a `Symbol`-typed method.
      module SymbolConverter
        def self.to_json(value : Symbol, json : JSON::Builder)
          json.string(value.to_s)
        end

        def self.from_json(pull : JSON::PullParser) : Symbol
          case raw = pull.read_string
          when "error"   then :error
          when "warning" then :warning
          when "info"    then :info
          else
            raise JSON::ParseException.new("Unknown issue level: #{raw.inspect}", *pull.location)
          end
        end
      end
    end

    # A named diagnostic check: a human label paired with the set of
    # issue IDs that, when present, count against this check. The CLI
    # uses this to render inline ✓/⚠/✗ lines in human output.
    #
    # `blocked_by` is this check's OWN abort conditions, on top of its
    # group's — for checks that need something the group as a whole does
    # not. The front-matter menu cross-check and the section-index walk
    # both need a parsed config, so neither can run when `config.toml` is
    # missing or broken, while the front-matter parse check in the same
    # group runs fine.
    record CheckSpec,
      label : String,
      issue_ids : Array(String),
      blocked_by : Array(String) = [] of String

    # A logical group of checks, surfaced under one heading in the CLI.
    # `:config` is rendered with the runtime config_path; other keys use
    # `default_heading` verbatim.
    #
    # `blocked_by` lists the issue ids that abort the group's scan before
    # the remaining checks can run (a missing config.toml, a missing
    # `templates/`, a missing `content/`). When one of them is present the
    # CLI renders every OTHER check in the group as skipped instead of as
    # a passing check — a green ✓ for a check that never executed reads as
    # reassurance the run has not earned.
    record CheckGroup,
      key : Symbol,
      default_heading : String,
      checks : Array(CheckSpec),
      blocked_by : Array(String) = [] of String

    # The config failures that abort `check_config` before it can produce
    # a `Models::Config`. Checks outside the config group that need one
    # name these too — see `CheckSpec#blocked_by`.
    CONFIG_BLOCKING_IDS = ["config-not-found", "config-parse-error"]

    # Single source of truth for the inline status lines emitted by
    # `hwaro doctor`. Anything that adds a new diagnostic to
    # `Services::Doctor` should also list its issue id(s) here so the
    # check shows up in human output. The previous duplication —
    # one list in this service and another in the CLI command — is
    # gone, so updating one place is enough.
    CHECK_GROUPS = [
      CheckGroup.new(
        key: :config,
        default_heading: "config.toml",
        checks: [
          CheckSpec.new("file present & parseable",
            ["config-not-found", "config-parse-error"]),
          CheckSpec.new("base_url, title",
            ["base-url-missing", "base-url-trailing-slash", "title-default"]),
          CheckSpec.new("sitemap (changefreq, priority)",
            ["sitemap-changefreq-invalid", "sitemap-priority-range"]),
          CheckSpec.new("taxonomies (duplicates)",
            ["taxonomy-duplicate", "language-duplicate"]),
          CheckSpec.new("search (format)",
            ["search-format-invalid"]),
          CheckSpec.new("languages (default_language resolves)",
            ["default-language-undefined"]),
          CheckSpec.new("versions (content paths exist)",
            ["version-path-missing"]),
          CheckSpec.new("markdown / pwa (valid enums)",
            ["markdown-math-engine-invalid", "pwa-cache-strategy-invalid", "pwa-display-invalid"]),
          CheckSpec.new("image processing (widths set)",
            ["image-processing-widths-empty"]),
          CheckSpec.new("deployment / related (refs resolve)",
            ["deployment-target-undefined", "related-taxonomy-undefined"]),
          CheckSpec.new("menus (parent references)",
            ["menu-parent-undefined"]),
          CheckSpec.new("referenced files & dirs",
            ["config-path-missing", "config-dir-missing"]),
          CheckSpec.new("build output (route evidence)",
            ["build-output-unusable", "build-output-stale"]),
          CheckSpec.new("sass (sources & enablement)",
            ["sass-dir-not-scanned", "sass-disabled-with-sources"]),
        ],
        blocked_by: CONFIG_BLOCKING_IDS,
      ),
      CheckGroup.new(
        key: :templates,
        default_heading: "templates/",
        checks: [
          CheckSpec.new("required files (page.html, section.html)",
            ["template-dir-missing", "template-required-missing"]),
          CheckSpec.new("template syntax",
            ["template-syntax-error", "template-read-error"]),
        ],
        blocked_by: ["template-dir-missing"],
      ),
      CheckGroup.new(
        key: :content,
        default_heading: "content/",
        checks: [
          CheckSpec.new("directory present",
            ["content-dir-missing"]),
          CheckSpec.new("front matter (TOML/YAML parse)",
            ["content-frontmatter-invalid", "content-read-error"]),
          CheckSpec.new("front matter menus (declared in config)",
            ["menu-undeclared"], blocked_by: CONFIG_BLOCKING_IDS),
          CheckSpec.new("section index files (_index.md)",
            ["structure-missing-index"], blocked_by: CONFIG_BLOCKING_IDS),
        ],
        blocked_by: ["content-dir-missing"],
      ),
    ]

    # Every id that aborts some check's scan, group-level or check-level.
    ALL_BLOCKING_IDS = begin
      ids = Set(String).new
      CHECK_GROUPS.each do |group|
        group.blocked_by.each { |id| ids << id }
        group.checks.each { |spec| spec.blocked_by.each { |id| ids << id } }
      end
      ids
    end
  end
end
