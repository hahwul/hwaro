# Doctor Service
#
# Diagnoses configuration, template, and structure issues in a Hwaro site.
# For content validation, use ContentValidator (hwaro tool validate).

require "json"
require "yaml"
require "toml"
require "crinja"
require "../models/config"
require "../utils/errors"
require "../utils/logger"
require "../utils/build_output"
require "../content/processors/markdown"
require "../content/processors/internal_link_resolver"
require "../core/build/parallel"
require "./config_snippets"
require "./content_lister"
require "./scaffolds/registry"

require "./doctor/registry"
require "./doctor/toml_scan"
require "./doctor/fix_config"
require "./doctor/config_checks"
require "./doctor/template_checks"
require "./doctor/content_checks"
require "./doctor/referenced_paths"

module Hwaro
  module Services
    class Doctor
      VALID_CHANGEFREQS    = %w[always hourly daily weekly monthly yearly never]
      VALID_SEARCH_FORMATS = %w[fuse_json fuse_javascript elasticlunr_json elasticlunr_javascript]
      # Mirrors `MarkdownConfig#initialize` defaults — only katex/mathjax
      # render math at runtime; other strings load nothing.
      VALID_MATH_ENGINES = %w[katex mathjax]

      # Delegate to ConfigSnippets for the single source of truth
      KNOWN_CONFIG_SECTIONS = ConfigSnippets::KNOWN_SECTIONS
      KNOWN_SUB_SECTIONS    = ConfigSnippets::KNOWN_SUB_SECTIONS

      # The scaffolded placeholder titles. `Models::Config` falls back to
      # "Hwaro Site" when `title` is absent, and every site `hwaro init`
      # creates ships its scaffold's placeholder — so checking only the
      # internal fallback meant the advisory never fired on the sites that
      # actually have a placeholder title, and it shipped into <title>, OG
      # tags and feeds unnoticed.
      #
      # Sourced from the scaffold registry rather than a hand-kept literal
      # list: hardcoding "My Hwaro Site" silently exempted every
      # `--scaffold blog|docs|book` site, which ships "My Blog" / "My Docs" /
      # "My Book". A new scaffold now joins the check automatically.
      class_getter default_titles : Set(String) do
        titles = Set{"Hwaro Site"}
        Scaffolds::Registry.all.each { |scaffold| titles << scaffold.config_title }
        titles
      end

      # `missing-config-<section>` ids are generated per config section
      # rather than enumerated, so `[doctor] ignore` validation matches
      # them by prefix.
      MISSING_SECTION_ID_PREFIX = "missing-config-"

      # Every static issue id doctor can emit, derived from `CHECK_GROUPS`
      # so a new diagnostic can't be validated against a list that forgot
      # it. `CHECK_GROUPS` is the registry; this is just its index.
      KNOWN_ISSUE_IDS = begin
        ids = Set(String).new
        CHECK_GROUPS.each { |group| group.checks.each { |spec| spec.issue_ids.each { |id| ids << id } } }
        ids
      end

      # True for any id `[doctor] ignore` can legitimately name.
      def self.known_issue_id?(id : String) : Bool
        KNOWN_ISSUE_IDS.includes?(id) || id.starts_with?(MISSING_SECTION_ID_PREFIX)
      end

      # The blocking ids the last `run` observed, recorded BEFORE the
      # `[doctor] ignore` filter. The CLI's skip rule keys off this rather
      # than off the returned issues: `content-dir-missing` is a warning,
      # so `ignore = ["content-dir-missing"]` used to hide it AND take the
      # whole `content/` group's skip state with it — every check in the
      # group went back to rendering ✓ for a site with no content
      # directory at all, which is the false all-clear this mechanism
      # exists to prevent. Silencing a report is not the same as the scan
      # having run.
      getter observed_blocking_ids : Set(String) = Set(String).new

      @content_dir : String
      @config_path : String
      @templates_dir : String
      @static_dir : String

      def initialize(@content_dir : String = "content", @config_path : String = "config.toml", @templates_dir : String = "templates", @static_dir : String = "static")
      end

      def run : Array(Issue)
        issues = [] of Issue
        config = check_config(issues)
        check_templates(issues)
        check_directory_structure(issues, config)
        check_content_frontmatter(issues, config)
        if config
          check_referenced_paths(issues, config)
          check_sass(issues, config)
        end
        @observed_blocking_ids = issues.map(&.id).to_set & ALL_BLOCKING_IDS

        ignore = config.try(&.doctor.ignore) || [] of String
        # `[doctor].ignore` exists to silence advisory noise. We refuse to
        # silence build-blocking errors here so a stray entry can't disable
        # CI gating — the `:error` level is reserved for issues that will
        # later fail `hwaro build` regardless. Say so out loud, though:
        # silently keeping a listed rule visible reads as a broken ignore
        # list rather than a deliberate refusal.
        unless ignore.empty?
          issues.select { |i| i.level == :error && ignore.includes?(i.id) }
            .map(&.id).uniq!.each do |id|
            Logger.warn "[doctor] ignore entry '#{id}' names an error-level rule and cannot be silenced."
          end
          # A misspelled entry silences nothing and used to do so in total
          # silence, so the user reads the still-reported issue as doctor
          # ignoring their ignore list. Name the typo instead.
          ignore.reject { |id| Doctor.known_issue_id?(id) }.uniq!.each do |id|
            Logger.warn "[doctor] ignore entry '#{id}' does not match any doctor rule id and has no effect."
          end
        end
        issues.reject { |i| i.level != :error && ignore.includes?(i.id) }
      end

      # Reusable Crinja env for parse-only checks. We never render, so
      # the env can be a default instance — loaders/extensions that the
      # production builder configures aren't needed to detect tag/syntax
      # mistakes.
      @template_parse_env : Crinja?
    end
  end
end
