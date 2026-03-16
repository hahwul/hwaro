require "html"
require "../../models/config"

module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        extend self

        # Pre-process markdown content before Markd parsing
        def preprocess(content : String, config : Models::MarkdownConfig) : String
          result = content
          result = preprocess_task_lists(result) if config.task_lists
          result = preprocess_definition_lists(result) if config.definition_lists
          result = preprocess_footnotes(result) if config.footnotes
          result = preprocess_math(result) if config.math
          result
        end

        # Post-process HTML after Markd rendering
        def postprocess(html : String, config : Models::MarkdownConfig) : String
          result = html
          result = postprocess_footnotes(result) if config.footnotes
          result = postprocess_mermaid(result) if config.mermaid
          result
        end

        # --- Task Lists ---
        # Converts - [ ] and - [x] to checkbox HTML in list items
        TASK_LIST_RE = /^(\s*[-*+]\s)\[([ xX])\]/m

        def preprocess_task_lists(content : String) : String
          content.gsub(TASK_LIST_RE) do |match|
            prefix = $1
            checked = $2.downcase == "x"
            if checked
              "#{prefix}<input type=\"checkbox\" checked disabled>"
            else
              "#{prefix}<input type=\"checkbox\" disabled>"
            end
          end
        end

        # --- Definition Lists ---
        # Converts Term\n: Definition syntax to <dl><dt><dd> HTML
        def preprocess_definition_lists(content : String) : String
          lines = content.split("\n")
          result = [] of String
          i = 0

          while i < lines.size
            line = lines[i]

            # Check if next line starts with ": " (definition)
            if i + 1 < lines.size && lines[i + 1].lstrip.starts_with?(": ")
              # This is a definition list
              result << "<dl>"
              while i < lines.size
                term = lines[i].strip
                break if term.empty?

                result << "<dt>#{HTML.escape(term)}</dt>"
                i += 1

                # Collect definitions for this term
                while i < lines.size && lines[i].lstrip.starts_with?(": ")
                  definition = lines[i].lstrip.lchop(": ").strip
                  result << "<dd>#{HTML.escape(definition)}</dd>"
                  i += 1
                end

                # Skip blank lines between term groups within the same dl
                if i < lines.size && lines[i].strip.empty? && i + 1 < lines.size && i + 2 < lines.size && lines[i + 2].lstrip.starts_with?(": ")
                  i += 1
                  next
                end
                break
              end
              result << "</dl>"
            else
              result << line
              i += 1
            end
          end

          result.join("\n")
        end

        # --- Footnotes ---
        # Pre-processing: extract footnote definitions and replace references with placeholders
        FOOTNOTE_DEF_RE     = /^\[\^([^\]]+)\]:\s*(.+?)$/m
        FOOTNOTE_REF_RE     = /\[\^([^\]]+)\]/
        FOOTNOTE_COMMENT_RE = /<!--HWARO-FN:([^:]+):(\d+):(.+?)-->/
        FOOTNOTE_BLOCK_RE   = /\n?<!--HWARO-FOOTNOTES-START-->.*?<!--HWARO-FOOTNOTES-END-->\n?/m

        def preprocess_footnotes(content : String) : String
          # Extract and remove footnote definitions
          footnotes = {} of String => String
          cleaned = content.gsub(FOOTNOTE_DEF_RE) do |_|
            footnotes[$~[1]] = $~[2]
            "" # Remove definition from content
          end

          return cleaned if footnotes.empty?

          # Replace references with superscript HTML placeholders
          counter = 0
          ref_order = {} of String => Int32
          result = cleaned.gsub(FOOTNOTE_REF_RE) do |full_match|
            key = $~[1]
            next full_match unless footnotes.has_key?(key)

            unless ref_order.has_key?(key)
              counter += 1
              ref_order[key] = counter
            end
            num = ref_order[key]
            escaped_key = HTML.escape(key)
            "<sup class=\"footnote-ref\"><a href=\"#fn-#{escaped_key}\" id=\"fnref-#{escaped_key}\">[#{num}]</a></sup>"
          end

          # Store footnotes data in a special HTML comment for postprocessing
          if ref_order.any?
            result += "\n<!--HWARO-FOOTNOTES-START-->\n"
            ref_order.each do |key, num|
              text = footnotes[key]? || ""
              # Escape --> in text to prevent premature comment close, and : to prevent parsing issues
              safe_key = key.gsub("-->", "—&gt;").gsub(":", "&#58;")
              safe_text = text.gsub("-->", "—&gt;").gsub(":", "&#58;")
              result += "<!--HWARO-FN:#{safe_key}:#{num}:#{safe_text}-->\n"
            end
            result += "<!--HWARO-FOOTNOTES-END-->\n"
          end

          result
        end

        # Post-processing: convert footnote comments to HTML section
        def postprocess_footnotes(html : String) : String
          return html unless html.includes?("<!--HWARO-FOOTNOTES-START-->")

          # Extract footnote data from comments
          footnotes = [] of {key: String, num: Int32, text: String}
          html.scan(FOOTNOTE_COMMENT_RE) do |match|
            # Unescape the comment-safe encoding
            key = match[1].gsub("&#58;", ":").gsub("—&gt;", "-->")
            text = match[3].gsub("&#58;", ":").gsub("—&gt;", "-->")
            num = match[2].to_i? || 0
            next if num <= 0
            footnotes << {key: key, num: num, text: text}
          end

          return html if footnotes.empty?

          # Build footnotes section
          section = String.build do |str|
            str << "<section class=\"footnotes\">\n<hr>\n<ol>\n"
            footnotes.sort_by { |fn| fn[:num] }.each do |fn|
              escaped_key = HTML.escape(fn[:key])
              escaped_text = HTML.escape(fn[:text])
              str << "<li id=\"fn-#{escaped_key}\">\n"
              str << "<p>#{escaped_text} <a href=\"#fnref-#{escaped_key}\" class=\"footnote-backref\">\u21A9</a></p>\n"
              str << "</li>\n"
            end
            str << "</ol>\n</section>\n"
          end

          # Replace the comment block with the rendered section
          html.sub(FOOTNOTE_BLOCK_RE, section)
        end

        # --- Math ---
        # Wraps math expressions in special HTML to prevent Markd from processing them
        def preprocess_math(content : String) : String
          # Display math: $$...$$ (multi-line)
          result = content.gsub(/\$\$(.*?)\$\$/m) do |_|
            escaped = $~[1].gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
            "<div class=\"math math-display\">\\[#{escaped}\\]</div>"
          end

          # Inline math: $...$ (single line, no space after opening or before closing $)
          result = result.gsub(/(?<![\\$])\$(?!\s)([^\n$]+?)(?<!\s)\$(?!\d)/) do |_|
            escaped = $~[1].gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
            "<span class=\"math math-inline\">\\(#{escaped}\\)</span>"
          end

          result
        end

        # --- Mermaid ---
        # Post-processing: convert mermaid code blocks to div elements
        def postprocess_mermaid(html : String) : String
          html.gsub(/<pre><code class="language-mermaid[^"]*">(.*?)<\/code><\/pre>/m) do |_|
            # Keep HTML entities as-is; the browser decodes them automatically
            # when Mermaid.js reads the element's textContent.
            # Only decode &amp; which Mermaid syntax may require in labels.
            code = $~[1].gsub("&amp;", "&")
            "<div class=\"mermaid\">#{code}</div>"
          end
        end
      end
    end
  end
end
