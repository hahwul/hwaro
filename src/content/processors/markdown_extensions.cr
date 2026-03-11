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
        FOOTNOTE_DEF_RE = /^\[\^([^\]]+)\]:\s*(.+?)$/m
        FOOTNOTE_REF_RE = /\[\^([^\]]+)\]/

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
            "<sup class=\"footnote-ref\"><a href=\"#fn-#{key}\" id=\"fnref-#{key}\">[#{num}]</a></sup>"
          end

          # Store footnotes data in a special HTML comment for postprocessing
          if ref_order.any?
            result += "\n<!--HWARO-FOOTNOTES-START-->\n"
            ref_order.each do |key, num|
              text = footnotes[key]? || ""
              result += "<!--HWARO-FN:#{key}:#{num}:#{text}-->\n"
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
          html.scan(/<!--HWARO-FN:([^:]+):(\d+):(.+?)-->/) do |match|
            footnotes << {key: match[1], num: match[2].to_i, text: match[3]}
          end

          return html if footnotes.empty?

          # Build footnotes section
          section = String.build do |str|
            str << "<section class=\"footnotes\">\n<hr>\n<ol>\n"
            footnotes.sort_by { |fn| fn[:num] }.each do |fn|
              str << "<li id=\"fn-#{fn[:key]}\">\n"
              str << "<p>#{fn[:text]} <a href=\"#fnref-#{fn[:key]}\" class=\"footnote-backref\">\u21A9</a></p>\n"
              str << "</li>\n"
            end
            str << "</ol>\n</section>\n"
          end

          # Replace the comment block with the rendered section
          html.sub(/\n?<!--HWARO-FOOTNOTES-START-->.*?<!--HWARO-FOOTNOTES-END-->\n?/m, section)
        end

        # --- Math ---
        # Wraps math expressions in special HTML to prevent Markd from processing them
        def preprocess_math(content : String) : String
          # Display math: $$...$$ (multi-line)
          result = content.gsub(/\$\$(.*?)\$\$/m) do |_|
            escaped = $~[1].gsub("<", "&lt;").gsub(">", "&gt;")
            "<div class=\"math math-display\">\\[#{escaped}\\]</div>"
          end

          # Inline math: $...$ (single line, no space after opening or before closing $)
          result = result.gsub(/(?<![\\$])\$(?!\s)([^\n$]+?)(?<!\s)\$(?!\d)/) do |_|
            escaped = $~[1].gsub("<", "&lt;").gsub(">", "&gt;")
            "<span class=\"math math-inline\">\\(#{escaped}\\)</span>"
          end

          result
        end

        # --- Mermaid ---
        # Post-processing: convert mermaid code blocks to div elements
        def postprocess_mermaid(html : String) : String
          html.gsub(/<pre><code class="language-mermaid[^"]*">(.*?)<\/code><\/pre>/m) do |_|
            code = $~[1]
              .gsub("&amp;", "&")
              .gsub("&lt;", "<")
              .gsub("&gt;", ">")
              .gsub("&quot;", "\"")
            "<div class=\"mermaid\">#{code}</div>"
          end
        end
      end
    end
  end
end
