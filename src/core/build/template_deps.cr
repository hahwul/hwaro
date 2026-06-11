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
        REFERENCE_TAG_RE = /\{%-?\s*(extends|include|import|from)\s+(.+?)\s*-?%\}/m

        # Per-tag argument shapes where the template name is a plain string
        # literal. The literal must account for the ENTIRE argument (modulo
        # the tag's own keywords) — a leading literal in an expression like
        # `{% include "partials/" ~ name %}` must NOT count as static.
        INCLUDE_ARG_RE = /\A\s*(?:"([^"]+)"|'([^']+)')\s*(?:ignore\s+missing\s*)?(?:with(?:out)?\s+context\s*)?\z/
        IMPORT_ARG_RE  = /\A\s*(?:"([^"]+)"|'([^']+)')\s+as\s+\w+\s*(?:with(?:out)?\s+context\s*)?\z/
        FROM_ARG_RE    = /\A\s*(?:"([^"]+)"|'([^']+)')\s+import\s+.+\z/m

        # True when any reference could not be resolved statically — the
        # graph is incomplete and callers must treat every template change
        # as affecting every page.
        getter? dynamic : Bool

        # Bare names of user shortcode templates (templates/shortcodes/*).
        getter shortcode_names : Array(String)

        @direct : Hash(String, Set(String))
        @content_hashes : Hash(String, String)
        @closures : Hash(String, Set(String))
        @closure_hashes : Hash(String, String)
        @shortcode_usage_patterns : Hash(String, Regex)
        # @closures and @closure_hashes fill lazily, and parallel render
        # workers reach them through cache.update → closure_hash — an
        # unsynchronized Hash insert under -Dpreview_mt.
        @lazy_mutex : Mutex

        def initialize(templates : Hash(String, String))
          @direct = {} of String => Set(String)
          @content_hashes = {} of String => String
          @closures = {} of String => Set(String)
          @closure_hashes = {} of String => String
          @lazy_mutex = Mutex.new
          @dynamic = false

          @shortcode_names = templates.keys
            .select(&.starts_with?("shortcodes/"))
            .map(&.lchop("shortcodes/"))

          @shortcode_usage_patterns = {} of String => Regex
          @shortcode_names.each do |name|
            # Covers all three invocation syntaxes the shortcode processor
            # accepts: direct/paren block `name(...)`, explicit call
            # `shortcode("name", ...)`, and the paren-less block form
            # `{% name key="v" %}`. Loose on purpose — an over-match only
            # causes an unnecessary rebuild, never a stale page.
            escaped = Regex.escape(name)
            @shortcode_usage_patterns[name] = /\b#{escaped}\s*\(|\bshortcode\(\s*["']#{escaped}["']|\{%-?\s*#{escaped}\b/
          end

          templates.each do |name, source|
            @content_hashes[name] = Digest::MD5.hexdigest(source)
            deps = Set(String).new
            source.scan(REFERENCE_TAG_RE) do |match|
              literal = case match[1]
                        when "extends", "include" then INCLUDE_ARG_RE.match(match[2])
                        when "import"             then IMPORT_ARG_RE.match(match[2])
                        else                           FROM_ARG_RE.match(match[2])
                        end
              if literal
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
          @lazy_mutex.synchronize { closure_unlocked(name) }
        end

        private def closure_unlocked(name : String) : Set(String)
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
        #
        # Memoized: sites have a handful of distinct (entry template,
        # shortcode set) combinations but compute this once or twice per
        # page on cached builds. The memo lives for this instance's
        # lifetime, which is exactly one template (re)load — invalidation
        # is automatic.
        def closure_hash(entry_template : String, shortcode_templates : Set(String) = Set(String).new) : String
          # NUL-separated: template names come from the filesystem and so
          # can never contain '\0', making the key collision-free. A visible
          # separator like '|' would let entry "a" + shortcode "b" collide
          # with an entry template literally named "a|b".
          memo_key = String.build do |io|
            io << entry_template
            shortcode_templates.to_a.sort!.each { |sc| io << '\0' << sc }
          end

          @lazy_mutex.synchronize do
            if cached = @closure_hashes[memo_key]?
              return cached
            end

            names = closure_unlocked(entry_template).dup
            shortcode_templates.each { |sc| names.concat(closure_unlocked(sc)) }

            digest = Digest::MD5.new
            names.to_a.sort!.each do |name|
              digest.update(name)
              digest.update("=")
              digest.update(@content_hashes[name]? || "<missing>")
              digest.update(";")
            end
            @closure_hashes[memo_key] = digest.final.hexstring
          end
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
