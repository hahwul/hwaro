# Shortcode processing module extracted from Builder
#
# Handles Jinja2/Crinja-style shortcode expansion in content:
# - Block shortcodes:  {% name(args) %}body{% end %}
# - Explicit calls:    {{ shortcode("name", args) }}
# - Direct calls:      {{ name(args) }}
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
        BLOCK_CLOSE_RE        = /\{\%\s*end\s*\%\}/

        # Process shortcodes in content (Jinja2/Crinja style)
        # Supports two syntax patterns:
        # 1. Explicit: {{ shortcode("name", arg1="value1", arg2="value2") }}
        # 2. Direct:   {{ name(arg1="value1", arg2="value2") }}
        private def process_shortcodes_jinja(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)? = nil, crinja_env_override : Crinja? = nil) : String
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
                io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results, crinja_env_override: crinja_env_override)
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

            io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results, crinja_env_override: crinja_env_override)
          end
        end

        private def process_shortcodes_in_text(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)? = nil, crinja_env_override : Crinja? = nil, depth : Int32 = 0) : String
          # 1. Block shortcodes: {% name(args) %}body{% end %}
          # Use stack-based parsing to correctly handle nested block shortcodes
          # of the same type, instead of a single regex that matches the first {% end %}.
          processed = process_block_shortcodes(content, templates, context, shortcode_results, crinja_env_override, depth)

          # 2. Explicit call: {{ shortcode("name", args) }}
          processed = processed.gsub(/\{\{\s*shortcode\s*\(\s*"([^"]+)"(?:\s*,\s*(.*?))?\s*\)\s*\}\}/) do |match|
            render_shortcode_result($1, $2?, templates, context, shortcode_results, match, warn_missing: true, crinja_env_override: crinja_env_override)
          end

          # 3. Direct call: {{ name(args) }}
          # Direct calls are also valid Crinja/Jinja function-call syntax
          # ({{ env("FOO") }}, {{ asset(name="x") }}, …), so we warn only when
          # the name resolves to neither a shortcode template nor a registered
          # Crinja function — that way real typos surface while legitimate
          # template-function calls in content pass through silently.
          processed.gsub(/\{\{\s*([a-zA-Z_][\w\-]*)\s*\((.*?)\)\s*\}\}/) do |match|
            render_shortcode_result($1, $2, templates, context, shortcode_results, match, warn_missing: true, crinja_env_override: crinja_env_override)
          end
        end

        # Stack-based block shortcode parser that correctly handles nested
        # block shortcodes of the same type. Scans for opening tags {% name(...) %}
        # and closing tags {% end %}, tracking nesting depth to pair them correctly.
        private def process_block_shortcodes(content : String, templates : Hash(String, String), context : Hash(String, Crinja::Value), shortcode_results : Hash(String, String)?, crinja_env_override : Crinja?, depth : Int32) : String
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
              body = process_shortcodes_in_text(body, templates, context, shortcode_results, crinja_env_override: crinja_env_override, depth: depth + 1)
            end

            extra_args = {"body" => body}
            original_text = content[open_start...pos]
            result << render_shortcode_result(name, args_str, templates, context, shortcode_results, original_text, warn_missing: true, extra_args: extra_args, crinja_env_override: crinja_env_override)
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
        ) : String
          template_key = "shortcodes/#{name}"
          template = templates[template_key]? || BuiltinShortcodes.templates[template_key]?

          unless template
            if warn_missing && !crinja_function?(name, crinja_env_override)
              warn_missing_shortcode(template_key)
            end
            return fallback
          end

          args = parse_shortcode_args_jinja(args_str)
          extra_args.try &.each { |k, v| args[k] = v }
          html = render_shortcode_jinja(template, args, context, crinja_env_override: crinja_env_override, shortcode_name: name)

          if results = shortcode_results
            placeholder = "HWARO-SHORTCODE-PLACEHOLDER-#{results.size}"
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
        private def render_shortcode_jinja(template : String, args : Hash(String, String), context : Hash(String, Crinja::Value), crinja_env_override : Crinja? = nil, shortcode_name : String? = nil) : String
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
            # that share @compiled_templates_cache.
            cache_key = template.hash ^ 0x5C0DE_CAFE_u64
            crinja_template = @compiled_templates_cache[cache_key]? || begin
              compiled = env.from_string(template)
              @compiled_templates_cache[cache_key] = compiled
              compiled
            end
            crinja_template.render(local_context)
          rescue ex : Crinja::TemplateError
            label = shortcode_name ? "shortcode '#{shortcode_name}'" : "shortcode"
            Logger.warn "Template error in #{label}: #{ex.message}"
            ""
          end
        end

        # Replace shortcode placeholders with their rendered HTML content
        private def replace_shortcode_placeholders(html : String, shortcode_results : Hash(String, String)) : String
          return html if shortcode_results.empty?
          html.gsub(/HWARO-SHORTCODE-PLACEHOLDER-\d+/) do |match|
            shortcode_results[match]? || match
          end
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
        rescue
          false
        end

        # Emit a "shortcode template not found" warning at most once per
        # template key per build to avoid spamming the log when the same
        # typo appears on many pages.
        private def warn_missing_shortcode(template_key : String) : Nil
          seen = (@shortcode_warnings_seen ||= Set(String).new)
          return if seen.includes?(template_key)
          seen << template_key
          Logger.warn "Shortcode template '#{template_key}' not found."
        end
      end
    end
  end
end
