# Markdown extensions — mermaid code blocks.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- Mermaid ---
        # Post-processing: convert mermaid code blocks to div elements
        def postprocess_mermaid(html : String) : String
          # Match the mermaid class as a full token only (`language-mermaid`
          # or `language-mermaid …`), not a prefix of `language-mermaidjs` /
          # `language-mermaid2`. Copy/hook paths already require exact
          # `lang.downcase == "mermaid"`.
          html.gsub(/<pre><code class="language-mermaid(?:\s[^"]*)?">(.*?)<\/code><\/pre>/m) do |_|
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
