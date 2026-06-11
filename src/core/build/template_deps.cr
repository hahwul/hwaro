# Static dependency graph between templates.
#
# Scans template sources for literal `{% extends %}`, `{% include %}`,
# `{% import %}`, and `{% from %}` references, plus shortcode invocations,
# and answers two questions the incremental machinery needs:
#
#   1. Which templates does a page's entry template transitively pull in?
#      (`closure_hash` — stored per page in the build cache so editing a
#      partial only invalidates the pages that actually render it)
#   2. Given a set of edited templates, which templates are affected?
#      (`dependents_closure` — drives selective re-render in `hwaro serve`)
#
# Correctness over cleverness: any reference the scanner cannot resolve
# statically (a variable include, a candidate list, …) marks the graph
# `dynamic?`, and callers fall back to the previous invalidate-everything
# behavior.

require "digest/md5"
require "set"

module Hwaro
  module Core
    module Build
      class TemplateDeps
        # `{% extends "base.html" %}`, `{% include 'partials/head.html' %}`,
        # `{% import "macros.html" as m %}`, `{% from "macros.html" import x %}`
        REFERENCE_TAG_RE = /\{%-?\s*(?:extends|include|import|from)\s+(.+?)\s*-?%\}/m

        # The first argument of the tag when it is a plain string literal.
        LITERAL_NAME_RE = /\A\s*(?:"([^"]+)"|'([^']+)')/

        # True when any reference could not be resolved statically — the
        # graph is incomplete and callers must treat every template change
        # as affecting every page.
        getter? dynamic : Bool

        # Bare names of user shortcode templates (templates/shortcodes/*).
        getter shortcode_names : Array(String)

        @direct : Hash(String, Set(String))
        @content_hashes : Hash(String, String)
        @closures : Hash(String, Set(String))
        @shortcode_usage_patterns : Hash(String, Regex)

        def initialize(templates : Hash(String, String))
          @direct = {} of String => Set(String)
          @content_hashes = {} of String => String
          @closures = {} of String => Set(String)
          @dynamic = false

          @shortcode_names = templates.keys
            .select(&.starts_with?("shortcodes/"))
            .map(&.lchop("shortcodes/"))

          @shortcode_usage_patterns = {} of String => Regex
          @shortcode_names.each do |name|
            # Matches `{% name(...) %}` and `{{ name(...) }}` loosely; an
            # over-match only causes an unnecessary rebuild, never a stale page.
            @shortcode_usage_patterns[name] = /\b#{Regex.escape(name)}\s*\(/
          end

          templates.each do |name, source|
            @content_hashes[name] = Digest::MD5.hexdigest(source)
            deps = Set(String).new
            source.scan(REFERENCE_TAG_RE) do |match|
              arg = match[1]
              if literal = LITERAL_NAME_RE.match(arg)
                deps << normalize(literal[1]? || literal[2]? || "")
              else
                @dynamic = true
              end
            end
            # Templates can invoke shortcodes too (process_shortcodes_in_text
            # runs over template bodies before compilation).
            @shortcode_names.each do |shortcode|
              deps << "shortcodes/#{shortcode}" if source.matches?(@shortcode_usage_patterns[shortcode])
            end
            @direct[name] = deps
          end
        end

        # Templates the page's content references via shortcode calls.
        def shortcodes_used_in(text : String) : Set(String)
          used = Set(String).new
          @shortcode_names.each do |name|
            used << "shortcodes/#{name}" if text.matches?(@shortcode_usage_patterns[name])
          end
          used
        end

        # Transitive dependency set of a template, including itself.
        # Unknown references stay in the set: they hash as "absent", so a
        # template appearing later changes the closure hash and re-renders.
        def closure(name : String) : Set(String)
          if cached = @closures[name]?
            return cached
          end

          result = Set(String).new
          stack = [name]
          while current = stack.pop?
            next unless result.add?(current)
            @direct[current]?.try(&.each { |dep| stack << dep })
          end
          @closures[name] = result
          result
        end

        # Stable fingerprint of everything that influences a page's rendered
        # template output: the entry template's closure plus the closures of
        # every shortcode template the page content invokes.
        def closure_hash(entry_template : String, shortcode_templates : Set(String) = Set(String).new) : String
          names = closure(entry_template).dup
          shortcode_templates.each { |sc| names.concat(closure(sc)) }

          digest = Digest::MD5.new
          names.to_a.sort!.each do |name|
            digest.update(name)
            digest.update("=")
            digest.update(@content_hashes[name]? || "<missing>")
            digest.update(";")
          end
          digest.final.hexstring
        end

        # All templates whose closure intersects `changed` — i.e. every
        # template that (transitively) extends, includes, or imports one of
        # the changed templates, plus the changed templates themselves.
        def dependents_closure(changed : Set(String)) : Set(String)
          affected = Set(String).new
          @direct.each_key do |name|
            affected << name unless (closure(name) & changed).empty?
          end
          # Changed templates that nothing references (and that aren't in
          # @direct, e.g. deleted-then-readded) still count as affected.
          affected.concat(changed)
          affected
        end

        private def normalize(reference : String) : String
          reference.sub(Builder::TEMPLATE_EXTENSION_REGEX, "")
        end
      end
    end
  end
end
