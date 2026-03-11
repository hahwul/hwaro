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

module Hwaro
  module Core
    module Build
      module ShortcodeProcessor
        SHORTCODE_ARGS_REGEX  = /(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^,\s]+))/
        # NOTE: POSITIONAL_ARG_REGEX is reserved for future use
        # POSITIONAL_ARG_REGEX  = /(?:^|,)\s*(?:"([^"]*)"|'([^']*)'|([^,\s=]+))/
        MAX_SHORTCODE_NESTING = 5

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
            buffer = String::Builder.new

            content.each_line(chomp: false) do |line|
              if in_fence
                io << line
                if line.match(/^\s*#{Regex.escape(fence_marker)}\s*$/)
                  in_fence = false
                  fence_marker = ""
                end
                next
              end

              if match = line.match(/^\s*(`{3,}|~{3,})/)
                io << process_shortcodes_in_text(buffer.to_s, templates, context, shortcode_results, crinja_env_override: crinja_env_override)
                buffer = String::Builder.new
                in_fence = true
                fence_marker = match[1]
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
          processed = content.gsub(/\{\%\s*([a-zA-Z_][\w\-]*)\s*\((.*?)\)\s*\%\}(.*?)\{\%\s*end\s*\%\}/m) do |match|
            name = $1
            args_str = $2
            body = $3.strip

            # Recursively process nested shortcodes in body (with depth limit)
            if depth < MAX_SHORTCODE_NESTING && (body.includes?("{{") || body.includes?("{%"))
              body = process_shortcodes_in_text(body, templates, context, shortcode_results, crinja_env_override: crinja_env_override, depth: depth + 1)
            end

            # NOTE: Markdown conversion of shortcode body is left to the shortcode
            # template itself (e.g. via {{ body | safe }} or a markdown filter).
            # Automatic conversion was removed to avoid unintended transformations
            # when body contains characters like *, _, or ` in non-markdown context.

            extra_args = {"body" => body}
            render_shortcode_result(name, args_str, templates, context, shortcode_results, match, warn_missing: true, extra_args: extra_args, crinja_env_override: crinja_env_override)
          end

          # 2. Explicit call: {{ shortcode("name", args) }}
          processed = processed.gsub(/\{\{\s*shortcode\s*\(\s*"([^"]+)"(?:\s*,\s*(.*?))?\s*\)\s*\}\}/) do |match|
            render_shortcode_result($1, $2?, templates, context, shortcode_results, match, warn_missing: true, crinja_env_override: crinja_env_override)
          end

          # 3. Direct call: {{ name(args) }}
          processed = processed.gsub(/\{\{\s*([a-zA-Z_][\w\-]*)\s*\((.*?)\)\s*\}\}/) do |match|
            render_shortcode_result($1, $2, templates, context, shortcode_results, match, warn_missing: false, crinja_env_override: crinja_env_override)
          end
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
          template = templates[template_key]?

          unless template
            Logger.warn "  [WARN] Shortcode template '#{template_key}' not found." if warn_missing
            return fallback
          end

          args = parse_shortcode_args_jinja(args_str)
          extra_args.try &.each { |k, v| args[k] = v }
          html = render_shortcode_jinja(template, args, context, crinja_env_override: crinja_env_override)

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
        private def render_shortcode_jinja(template : String, args : Hash(String, String), context : Hash(String, Crinja::Value), crinja_env_override : Crinja? = nil) : String
          env = crinja_env_override || crinja_env
          vars = context.dup
          args.each do |key, value|
            vars[key] = Crinja::Value.new(value)
          end

          begin
            crinja_template = env.from_string(template)
            crinja_template.render(vars)
          rescue ex : Crinja::TemplateError
            Logger.warn "  [WARN] Shortcode template error: #{ex.message}"
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
      end
    end
  end
end
