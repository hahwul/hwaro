# Shortcode processing module extracted from Builder
#
# Handles Jinja2/Crinja-style shortcode expansion in content:
# - Block shortcodes:  {% name(args) %}body{% end %}   or   {% name(args) %}body{% endname %}
# - Explicit calls:    {{ shortcode("name", args) }}
# - Direct calls:      {{ name(args) }}
#
# Both bare {% end %} and named {% endNAME %} closers are supported (localized normalization).
#
# Shortcodes inside fenced code blocks (``` / ~~~) are left untouched
# so documentation can show literal `{{ ... }}` examples safely.

require "crinja"
require "../../utils/logger"
require "./builtin_shortcodes"

module Hwaro
  module Core
    module Build
      module ShortcodeProcessor
        SHORTCODE_ARGS_REGEX = /(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^,\s]+))/
        # NOTE: POSITIONAL_ARG_REGEX is reserved for future use
        # POSITIONAL_ARG_REGEX  = /(?:^|,)\s*(?:"([^"]*)"|'([^']*)'|([^,\s=]+))/
        MAX_SHORTCODE_NESTING = 5
        BLOCK_OPEN_RE         = /\{\%\s*([a-zA-Z_][\w\-]*)\s*(?:\((.*?)\)|((?:\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^,%\s]+)\s*,?\s*)*))\s*\%\}/
        # Support both bare {% end %} and named {% endNAME %}.
        BLOCK_CLOSE_RE = /\{\%\s*end(?:\s+[a-zA-Z_][\w\-]*)?\s*\%\}/i

        # Placeholder left in the content stream for each rendered shortcode
        # before Markdown runs. HTML-comment form so CommonMark treats it as
        # an HTML block (type 2) when on its own line — otherwise block-level
        # shortcode output ends up wrapped in a stray <p>. Inline usage still
        # works because comments are preserved verbatim inside paragraphs.
        # The %d is substituted with the placeholder index at emit time, and
        # the regex is used by `replace_shortcode_placeholders` after Markdown.
        SHORTCODE_PLACEHOLDER_PREFIX = "<!--HWARO-SHORTCODE-PLACEHOLDER-"
        SHORTCODE_PLACEHOLDER_SUFFIX = "-->"
        SHORTCODE_PLACEHOLDER_RE     = /#{Regex.escape(SHORTCODE_PLACEHOLDER_PREFIX)}\d+#{Regex.escape(SHORTCODE_PLACEHOLDER_SUFFIX)}/

        # Matches CommonMark-style inline code spans on a single line
        # (1 to 3 leading backticks; the same count must close the span).
        # Multi-line inline spans are rare and intentionally not handled —
        # those are usually fenced blocks, which the line-based outer
        # loop in `process_shortcodes_jinja` already skips.
        INLINE_CODE_RE = /(`{1,3})((?:(?!\1)[^\n])+?)\1/

        # Fast pre-filter used by the render hot path (see render.cr).
        # Returns true only when {{ or {% appear *outside* fenced code blocks
        # (``` / ~~~) and *outside* inline code spans. This lets us skip the
        # expensive build_template_variables + full shortcode processing for
        # the very common case of documentation pages that only show literal
        # shortcode examples inside code regions.
        def content_may_contain_shortcodes?(content : String) : Bool
          return false unless content.includes?("{{") || content.includes?("{%")

          in_fence = false
          fence_marker = ""
          fence_close_regex : Regex? = nil

          content.each_line(chomp: false) do |line|
            if in_fence
              if fence_close_regex.try(&.match(line))
                in_fence = false
                fence_marker = ""
                fence_close_regex = nil
              end
              next
            end

            if match = line.match(/^\s*(`{3,}|~{3,})/)
              in_fence = true
              fence_marker = match[1]
              fence_close_regex = Regex.new("^\\s*#{Regex.escape(fence_marker)}\\s*$")
              next
            end

            # Outside fence: check whether any {{ or {% survives inline-code stripping
            if line.includes?("{{") || line.includes?("{%")
              if has_shortcode_token_outside_inline_code?(line)
                return true
              end
            end
          end

          false
        end

        private def has_shortcode_token_outside_inline_code?(line : String) : Bool
          pos = 0
          while match = INLINE_CODE_RE.match(line, pos)
            before = line[pos...match.begin]
            return true if before.includes?("{{") || before.includes?("{%")

            pos = match.begin + match[0].size
          end

          tail = line[pos..]
          tail.includes?("{{") || tail.includes?("{%")
        end

        # Process shortcodes in content (Jinja2/Crinja style)
        # Supports two syntax patterns:
        # 1. Explicit: {{ shortcode("name", arg1="value1", arg2="value2") }}
        # 2. Direct:   {{ name(arg1="value1", arg2="value2") }}
        private def process_shortcodes_jinja(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)? = nil, crinja_env_override : Crinja? = nil, template_cache_override : Hash(UInt64, Crinja::Template)? = nil) : String
          # Avoid processing shortcodes inside fenced code blocks (``` / ~~~),
          # so documentation can show literal `{{ ... }}` examples safely.
          String.build do |io|
            in_fence = false
            fence_marker = ""
            fence_close_regex : Regex? = nil
            buffer = String::Builder.new

            content.each_line(chomp: false) do |line|
              if in_fence
                io << line
                if fence_close_regex.try(&.match(line))
                  in_fence = false
                  fence_marker = ""
                  fence_close_regex = nil
                end
                next
              end

              if match = line.match(/^\s*(`{3,}|~{3,})/)
                io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override)
                buffer = String::Builder.new
                in_fence = true
                fence_marker = match[1]
                # Compile the close-fence regex once per fenced block
                fence_close_regex = Regex.new("^\\s*#{Regex.escape(fence_marker)}\\s*$")
                io << line
              else
                buffer << line
              end
            end

            io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override)
          end
        end

        private def process_shortcodes_in_text(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)? = nil, crinja_env_override : Crinja? = nil, template_cache_override : Hash(UInt64, Crinja::Template)? = nil, depth : Int32 = 0) : String
          # Inline code spans (`…`, ``…``) are opaque to the shortcode
          # processor — running shortcodes inside `<code>` would both
          # change the visible source the author meant to display and
          # leak placeholder comments into the rendered HTML / search
          # index after Markdown HTML-escapes them inside `<code>`.
          # Mirror the protection that fenced code blocks already get
          # in `process_shortcodes_jinja`.
          process_outside_inline_code(content) do |chunk|
            process_shortcodes_in_chunk(chunk, templates, context, shortcode_results, crinja_env_override, template_cache_override, depth)
          end
        end

        private def process_shortcodes_in_chunk(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)?, crinja_env_override : Crinja?, template_cache_override : Hash(UInt64, Crinja::Template)?, depth : Int32) : String
          # Localized normalization for named closers (only affects shortcode block content).
          # Avoid touching real Jinja/Crinja control tags (endif, endfor, etc.).
          normalized = content.gsub(/\{\%\s*end\s*(?!if|for|macro|block|call|set|with|autoescape|raw|filter|trans|pluralize|comment)[a-zA-Z_][\w\-]*\s*\%\}/i, "{% end %}")

          # 1. Block shortcodes
          processed = process_block_shortcodes(normalized, templates, context, shortcode_results, crinja_env_override, template_cache_override, depth)

          # 2. Explicit call: {{ shortcode("name", args) }}
          processed = processed.gsub(/\{\{\s*shortcode\s*\(\s*"([^"]+)"(?:\s*,\s*(.*?))?\s*\)\s*\}\}/) do |match|
            render_shortcode_result($1, $2?, templates, context, shortcode_results, match, warn_missing: true, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override)
          end

          # 3. Direct call: {{ name(args) }}
          # Direct calls are also valid Crinja/Jinja function-call syntax
          # ({{ env("FOO") }}, {{ asset(name="x") }}, …), so we warn only when
          # the name resolves to neither a shortcode template nor a registered
          # Crinja function — that way real typos surface while legitimate
          # template-function calls in content pass through silently.
          processed.gsub(/\{\{\s*([a-zA-Z_][\w\-]*)\s*\((.*?)\)\s*\}\}/) do |match|
            render_shortcode_result($1, $2, templates, context, shortcode_results, match, warn_missing: true, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override)
          end
        end

        # Yield each contiguous run of non-inline-code text to `block`,
        # passing inline code spans (`…`, ``…``) through verbatim. The
        # caller reassembles the result; only non-code chunks are subject
        # to shortcode substitution.
        private def process_outside_inline_code(content : String, & : String -> String) : String
          result = String::Builder.new
          pos = 0
          while match = INLINE_CODE_RE.match(content, pos)
            match_start = match.begin
            result << yield content[pos...match_start]
            result << match[0]
            pos = match_start + match[0].size
          end
          result << yield content[pos..]
          result.to_s
        end

        # Stack-based block shortcode parser that correctly handles nested
        # block shortcodes of the same type. Scans for opening tags {% name(...) %}
        # and closing tags {% end %}, tracking nesting depth to pair them correctly.
        private def process_block_shortcodes(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)?, crinja_env_override : Crinja?, template_cache_override : Hash(UInt64, Crinja::Template)?, depth : Int32) : String
          open_re = BLOCK_OPEN_RE
          close_re = BLOCK_CLOSE_RE

          result = String::Builder.new
          pos = 0

          while pos < content.size
            # Find next opening tag
            open_match = open_re.match(content, pos)
            # Find next closing tag (to handle stray {% end %} gracefully)
            close_match = close_re.match(content, pos)

            # No more opening tags — append rest and done
            unless open_match
              result << content[pos..]
              break
            end

            open_start = open_match.begin

            # If a close tag appears before the next open tag, it's unmatched — emit as-is
            if close_match
              close_start = close_match.begin
              if close_start < open_start
                result << content[pos..close_start + close_match[0].size - 1]
                pos = close_start + close_match[0].size
                next
              end
            end

            # Emit text before the opening tag
            result << content[pos...open_start]

            name = open_match[1]
            args_str = open_match[2]? || open_match[3]?
            body_start = open_start + open_match[0].size

            # `{% end %}` is the closing-tag literal; BLOCK_OPEN_RE happens to
            # match it too (since `end` is a valid identifier), but treating
            # it as an opening tag would silently consume a stray close. Emit
            # it as-is so unmatched `{% end %}` reads as plain text.
            if name == "end"
              result << open_match[0]
              pos = body_start
              next
            end

            # Find the matching {% end %} by tracking nesting depth
            nesting = 1
            scan_pos = body_start
            body_end = nil

            while nesting > 0 && scan_pos < content.size
              next_open = open_re.match(content, scan_pos)
              next_close = close_re.match(content, scan_pos)

              break unless next_close
              next_close_start = next_close.begin

              if next_open
                next_open_start = next_open.begin
                if next_open_start < next_close_start
                  nesting += 1
                  scan_pos = next_open_start + next_open[0].size
                  next
                end
              end

              nesting -= 1
              if nesting == 0
                body_end = next_close_start
                pos = next_close_start + next_close[0].size
              else
                scan_pos = next_close_start + next_close[0].size
              end
            end

            unless body_end
              # No matching {% end %} found — emit the opening tag as literal text
              result << open_match[0]
              pos = body_start
              next
            end

            body = content[body_start...body_end].strip

            # Recursively process nested shortcodes in body (with depth limit)
            if depth < MAX_SHORTCODE_NESTING && (body.includes?("{{") || body.includes?("{%"))
              body = process_shortcodes_in_text(body, templates, context, shortcode_results, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, depth: depth + 1)
            end

            extra_args = {"body" => body}
            original_text = content[open_start...pos]
            result << render_shortcode_result(name, args_str, templates, context, shortcode_results, original_text, warn_missing: true, extra_args: extra_args, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override)
          end

          result.to_s
        end

        # Shared helper: look up a shortcode template, render it, and either
        # return the HTML directly or store it behind a placeholder so that
        # Markdown processing doesn't mangle it.
        private def render_shortcode_result(
          name : String,
          args_str : String?,
          templates : Hash(String, String),
          context : Hash(String, Crinja::Value),
          shortcode_results : Hash(String, String)?,
          fallback : String,
          warn_missing : Bool = true,
          extra_args : Hash(String, String)? = nil,
          crinja_env_override : Crinja? = nil,
          template_cache_override : Hash(UInt64, Crinja::Template)? = nil,
        ) : String
          template_key = "shortcodes/#{name}"
          template = templates[template_key]? || BuiltinShortcodes.templates[template_key]?

          unless template
            # Direct-call syntax (`{{ name(args) }}`) doubles as Crinja's
            # function-call syntax — `env`, `asset`, `url_for`, …, are
            # legitimate references that the page-template engine will
            # resolve later. Pass those through untouched.
            return fallback if crinja_function?(name, crinja_env_override)

            warn_missing_shortcode(template_key) if warn_missing

            # Drop the call instead of leaking `{{ name(args) }}` into the
            # rendered HTML and search index. Use the placeholder pipeline
            # so block-level missing calls don't get wrapped in a stray
            # `<p>`, mirroring how rendered shortcodes are handled.
            placeholder_html = "<!-- hwaro: missing shortcode '#{name}' -->"
            if results = shortcode_results
              placeholder = "#{SHORTCODE_PLACEHOLDER_PREFIX}#{results.size}#{SHORTCODE_PLACEHOLDER_SUFFIX}"
              results[placeholder] = placeholder_html
              return placeholder
            end
            return placeholder_html
          end

          args = parse_shortcode_args_jinja(args_str)
          extra_args.try &.each { |k, v| args[k] = v }

          # Built-in shortcodes read named slots (`{{ id }}`, `{{ src }}`, ...),
          # so the documented positional form (`{{ youtube("ID") }}`) only
          # reaches them after we alias each `_N` to the corresponding named
          # parameter declared in `BuiltinShortcodes::POSITIONAL_PARAMS`.
          # Named arguments always win — we only fill slots the caller did
          # not already provide.
          if positional = BuiltinShortcodes.positional_params(template_key)
            positional.each_with_index do |param_name, idx|
              next if args.has_key?(param_name)
              if value = args["_#{idx}"]?
                args[param_name] = value
              end
            end
          end

          html = render_shortcode_jinja(template, args, context, crinja_env_override: crinja_env_override, template_cache_override: template_cache_override, shortcode_name: name)

          if results = shortcode_results
            placeholder = "#{SHORTCODE_PLACEHOLDER_PREFIX}#{results.size}#{SHORTCODE_PLACEHOLDER_SUFFIX}"
            results[placeholder] = html
            placeholder
          else
            html
          end
        end

        # Parse shortcode arguments — supports both named and positional
        # Named:      key="value", key='value', key=value
        # Positional:  "value", 'value', value (assigned as _0, _1, ...)
        private def parse_shortcode_args_jinja(args_str : String?) : Hash(String, String)
          args = {} of String => String
          return args unless args_str
          return args if args_str.strip.empty?

          # First try named arguments
          has_named = args_str.includes?("=")
          if has_named
            args_str.scan(SHORTCODE_ARGS_REGEX) do |match|
              key = match[1]
              value = match[2]? || match[3]? || match[4]? || ""
              args[key] = value
            end
          end

          # If no named args found, try positional
          if args.empty?
            idx = 0
            args_str.split(",").each do |part|
              value = part.strip
              # Strip surrounding quotes
              if (value.starts_with?('"') && value.ends_with?('"')) ||
                 (value.starts_with?('\'') && value.ends_with?('\''))
                value = value[1..-2]
              end
              next if value.empty?
              args["_#{idx}"] = value
              idx += 1
            end
          end

          args
        end

        # Render a shortcode template with Crinja
        private def render_shortcode_jinja(template : String, args : Hash(String, String), context : Hash(String, Crinja::Value), crinja_env_override : Crinja? = nil, template_cache_override : Hash(UInt64, Crinja::Template)? = nil, shortcode_name : String? = nil) : String
          env = crinja_env_override || crinja_env

          # Use a local copy of context with args merged to avoid mutating
          # shared state — the original inject-then-restore approach was unsafe
          # under parallel builds where multiple fibers share the same context.
          local_context = context.dup
          args.each { |key, value| local_context[key] = Crinja::Value.new(value) }

          begin
            # Cache compiled shortcode templates by content hash to avoid
            # re-parsing the template AST on every shortcode invocation.
            # XOR with a salt to avoid collisions with page template cache entries
            # that share the same cache map.
            #
            # A `Crinja::Template` is permanently bound to the env it was parsed
            # with (`Template#render` swaps `@context` on *that* env), so a
            # cached template MUST only ever be rendered on the env that
            # compiled it. In the parallel path each worker passes its own env
            # AND its own cache (`template_cache_override`); using that
            # worker-local cache keeps every template bound to, and rendered on,
            # the worker's own env — no cross-worker env mutation, and no mutex
            # needed since a single fiber owns the cache. Only the shared
            # fallback cache (sequential path) needs the reentrant mutex.
            cache_key = template.hash ^ 0x5C0DE_CAFE_u64
            crinja_template = if wcache = template_cache_override
                                wcache[cache_key]? || begin
                                  compiled = env.from_string(template)
                                  wcache[cache_key] = compiled
                                  compiled
                                end
                              else
                                @crinja_cache_mutex.synchronize do
                                  @compiled_templates_cache[cache_key]? || begin
                                    compiled = env.from_string(template)
                                    @compiled_templates_cache[cache_key] = compiled
                                    compiled
                                  end
                                end
                              end
            crinja_template.render(local_context)
          rescue ex : Crinja::TemplateError
            label = shortcode_name ? "shortcode '#{shortcode_name}'" : "shortcode"
            Logger.warn "Template error in #{label}: #{ex.message}"
            ""
          end
        end

        # Replace shortcode placeholders with their rendered HTML content.
        #
        # Block shortcodes can nest, and the inner placeholder gets baked
        # into the outer template's `{{ body }}` before either of them
        # actually lands in the rendered HTML. A single gsub pass would
        # only resolve the outermost placeholder, leaving an
        # `<!--HWARO-SHORTCODE-PLACEHOLDER-N-->` artifact one level
        # inwards. Loop until the result stops changing (or until we hit
        # the same depth limit the recursive renderer uses) so every
        # nested level resolves.
        private def replace_shortcode_placeholders(html : String, shortcode_results : Hash(String, String)) : String
          return html if shortcode_results.empty?
          result = html
          (MAX_SHORTCODE_NESTING + 1).times do
            replaced = result.gsub(SHORTCODE_PLACEHOLDER_RE) do |match|
              shortcode_results[match]? || match
            end
            return replaced if replaced == result
            result = replaced
          end
          result
        end

        # True when `name` is a registered Crinja function in the env used
        # for template rendering. Direct shortcode calls ({{ name(args) }})
        # and template function calls share syntax, so this check lets the
        # shortcode processor silent-pass-through legitimate function calls
        # like `env`, `asset`, `url_for`, `get_url`, … while still warning
        # on names that aren't registered anywhere.
        private def crinja_function?(name : String, crinja_env_override : Crinja?) : Bool
          env = crinja_env_override || crinja_env
          env.functions.has_key?(name)
        rescue Exception
          false
        end

        # Emit a "shortcode template not found" warning at most once per
        # template key per build to avoid spamming the log when the same
        # typo appears on many pages.
        #
        # MT note: `Set#includes?` + `Set#<<` is a check-then-write race
        # under `-Dpreview_mt`. Two workers hitting the same missing
        # shortcode could each emit one warning before the other had a
        # chance to record it. Cheap to guard with the shared crinja mutex.
        private def warn_missing_shortcode(template_key : String) : Nil
          should_warn = @crinja_cache_mutex.synchronize do
            seen = (@shortcode_warnings_seen ||= Set(String).new)
            seen.add?(template_key)
          end
          return unless should_warn
          Logger.warn "Shortcode template '#{template_key}' not found."
        end
      end
    end
  end
end
