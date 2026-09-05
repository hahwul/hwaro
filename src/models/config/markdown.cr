# Config section — [markdown].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # Markdown parser configuration
    # Maps to Markd::Options for controlling markdown parsing behavior
    class MarkdownConfig
      property safe : Bool              # If true, raw HTML will not be passed through (replaced by comments)
      property lazy_loading : Bool      # If true, adds loading="lazy" to img tags
      property emoji : Bool             # If true, converts emoji shortcodes (e.g. :smile:) to emoji characters
      property footnotes : Bool         # If true, enables footnote syntax ([^1])
      property task_lists : Bool        # If true, enables task list syntax (- [ ] / - [x])
      property definition_lists : Bool  # If true, enables definition list syntax (Term\n: Definition)
      property mermaid : Bool           # If true, renders ```mermaid blocks as diagrams
      property math : Bool              # If true, enables math syntax ($...$ and $$...$$)
      property math_engine : String     # "katex" or "mathjax"
      property admonitions : Bool       # If true, GitHub-style `> [!NOTE]` blockquotes become admonition <div>s
      property heading_ids : Bool       # If true, `## Heading {#custom-id}` sets an explicit id
      property ins : Bool               # If true, enables inserted-text syntax (++ins++)
      property mark : Bool              # If true, enables highlighted-text syntax (==mark==)
      property sub : Bool               # If true, enables subscript syntax (~sub~)
      property sup : Bool               # If true, enables superscript syntax (^sup^)
      property attributes : Bool        # If true, enables `{#id .class key=val}` attribute blocks on headings/images
      property smart_punctuation : Bool # If true, straight quotes/dashes/ellipses become typographic ones (markd smart mode)
      # Site-wide policy for absolute http(s) links in rendered markdown
      # (Zola parity). target_blank also adds rel="noopener".
      property external_links_target_blank : Bool
      property external_links_no_follow : Bool
      property external_links_no_referrer : Bool
      # If true, task-list markup gets GFM's classes (task-list-item /
      # task-list-item-checkbox / contains-task-list) for CSS parity.
      property task_list_classes : Bool
      # Site-wide heading anchor links: "none" (default), "left", or
      # "right" (Zola's values; "before"/"after" accepted as aliases for
      # the internal style names). Page front matter overrides per page.
      property insert_anchor_links : String
      # If true, enables `:::type Title` … `:::` custom containers,
      # rendered with the admonition markup (shared CSS). Unsupported
      # under safe mode (the raw <div> wrapper would be stripped).
      property containers : Bool

      def initialize
        @safe = false
        @lazy_loading = false
        @emoji = false
        @footnotes = true
        @task_lists = true
        @definition_lists = true
        @mermaid = false
        @math = false
        @math_engine = "katex"
        @admonitions = true
        @heading_ids = true
        @ins = false
        @mark = false
        @sub = false
        @sup = false
        @attributes = false
        @smart_punctuation = false
        @external_links_target_blank = false
        @external_links_no_follow = false
        @external_links_no_referrer = false
        @task_list_classes = false
        @insert_anchor_links = "none"
        @containers = false
      end

      # Compact fingerprint of every field that changes rendered body HTML.
      # Keys Processor::Markdown.render_body_cached's memo so entries from a
      # previous config (e.g. after a config reload in `serve`) can't be
      # served for a build running with different markdown options.
      def cache_fingerprint : String
        String.build(21 + @math_engine.bytesize) do |io|
          io << (@safe ? '1' : '0') << (@lazy_loading ? '1' : '0') << (@emoji ? '1' : '0')
          io << (@footnotes ? '1' : '0') << (@task_lists ? '1' : '0') << (@definition_lists ? '1' : '0')
          io << (@mermaid ? '1' : '0') << (@math ? '1' : '0') << (@admonitions ? '1' : '0')
          io << (@heading_ids ? '1' : '0')
          io << (@ins ? '1' : '0') << (@mark ? '1' : '0') << (@sub ? '1' : '0')
          io << (@sup ? '1' : '0') << (@attributes ? '1' : '0') << (@smart_punctuation ? '1' : '0')
          io << (@external_links_target_blank ? '1' : '0') << (@external_links_no_follow ? '1' : '0')
          io << (@external_links_no_referrer ? '1' : '0') << (@task_list_classes ? '1' : '0')
          io << (@containers ? '1' : '0')
          io << @math_engine << ':' << @insert_anchor_links
        end
      end

      # Generate CDN script tags for the math engine. The markdown processor
      # emits `\(…\)`/`\[…\]` wrappers with `class="math math-{inline,display}"`
      # but doesn't load the renderer — without these tags the math reaches
      # the browser as literal TeX. Templates can opt out by overriding the
      # `{{ math_tags }}` variable or by leaving `math = false` and inlining
      # their own includes via [auto_includes].
      def math_tags : String
        return "" unless @math
        case @math_engine
        when "katex"
          # auto-render finds class="math math-{inline,display}" automatically
          # and replaces the inner TeX with rendered KaTeX. Pinned KaTeX 0.16.x
          # to avoid surprise major-version churn in build outputs.
          <<-HTML.gsub('\n', "")
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.css">
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.js"></script>
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/contrib/auto-render.min.js" onload="renderMathInElement(document.body);"></script>
            HTML
        when "mathjax"
          # MathJax 3 reads `class="math math-*"` via the `[tex]` extension
          # configured to recognise `\(…\)` and `\[…\]` delimiters (which is
          # how the markdown processor emits them).
          <<-HTML.gsub('\n', "")
            <script>window.MathJax={tex:{inlineMath:[["\\\\(","\\\\)"]],displayMath:[["\\\\[","\\\\]"]]}};</script>
            <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
            HTML
        else
          ""
        end
      end

      # Generate the Mermaid.js script tag. Mirrors `math_tags`: the markdown
      # processor emits `<div class="mermaid">…</div>`, but without a renderer
      # those blocks ship to the browser as DOT-like source text. Pinned to
      # 10.x to avoid major-version drift.
      def mermaid_tags : String
        return "" unless @mermaid
        <<-HTML.gsub('\n', "")
          <script type="module">
            import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs";
            mermaid.initialize({ startOnLoad: true });
          </script>
          HTML
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_markdown(config : Config)
        return unless s = config.raw["markdown"]?.try(&.as_h?)

        config.markdown.safe = bool_value(s["safe"]?, config.markdown.safe)
        config.markdown.lazy_loading = bool_value(s["lazy_loading"]?, config.markdown.lazy_loading)
        config.markdown.emoji = bool_value(s["emoji"]?, config.markdown.emoji)
        config.markdown.footnotes = bool_value(s["footnotes"]?, config.markdown.footnotes)
        config.markdown.task_lists = bool_value(s["task_lists"]?, config.markdown.task_lists)
        config.markdown.definition_lists = bool_value(s["definition_lists"]?, config.markdown.definition_lists)
        config.markdown.mermaid = bool_value(s["mermaid"]?, config.markdown.mermaid)
        config.markdown.math = bool_value(s["math"]?, config.markdown.math)
        if engine = s["math_engine"]?.try(&.as_s?)
          config.markdown.math_engine = engine
        end
        config.markdown.admonitions = bool_value(s["admonitions"]?, config.markdown.admonitions)
        config.markdown.heading_ids = bool_value(s["heading_ids"]?, config.markdown.heading_ids)
        config.markdown.ins = bool_value(s["ins"]?, config.markdown.ins)
        config.markdown.mark = bool_value(s["mark"]?, config.markdown.mark)
        config.markdown.sub = bool_value(s["sub"]?, config.markdown.sub)
        config.markdown.sup = bool_value(s["sup"]?, config.markdown.sup)
        config.markdown.attributes = bool_value(s["attributes"]?, config.markdown.attributes)
        config.markdown.smart_punctuation = bool_value(s["smart_punctuation"]?, config.markdown.smart_punctuation)
        config.markdown.external_links_target_blank = bool_value(s["external_links_target_blank"]?, config.markdown.external_links_target_blank)
        config.markdown.external_links_no_follow = bool_value(s["external_links_no_follow"]?, config.markdown.external_links_no_follow)
        config.markdown.external_links_no_referrer = bool_value(s["external_links_no_referrer"]?, config.markdown.external_links_no_referrer)
        config.markdown.task_list_classes = bool_value(s["task_list_classes"]?, config.markdown.task_list_classes)
        config.markdown.containers = bool_value(s["containers"]?, config.markdown.containers)
        if anchors = s["insert_anchor_links"]?.try(&.as_s?)
          if anchors.in?("none", "left", "right", "before", "after")
            config.markdown.insert_anchor_links = anchors
          else
            # Zola's "heading" style (whole heading as a link) is not
            # implemented — warn and keep the default rather than silently
            # rendering something different from what was asked for.
            Logger.warn "config: unknown [markdown] insert_anchor_links value #{anchors.inspect} (expected none/left/right); using \"none\""
          end
        end
      end
    end
  end
end
