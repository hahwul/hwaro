# Config section — [highlight].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # Syntax highlighting configuration
    class HighlightConfig
      property enabled : Bool
      property theme : String
      property use_cdn : Bool
      # "server" (default) highlights at build time (Tartrazine lexers,
      # hljs-compatible CSS classes) so no JavaScript ships; "client" injects
      # Highlight.js and highlights in the browser — theme CSS keeps working
      # either way.
      property mode : String
      # Global default for fence-level `linenos` (see FenceOptions): when
      # true, every fenced code block with a language gets line numbers
      # unless it opts out with a per-block `{linenos=false}`. Off by
      # default so existing output is unaffected.
      property line_numbers : Bool
      # Adds a copy-to-clipboard button to fenced code blocks (per-block
      # `{copy=false}`/`{copy=true}` overrides). Off by default so existing
      # output is byte-identical.
      property copy : Bool

      def initialize
        @enabled = true
        @theme = "github"
        @use_cdn = true
        @mode = "server"
        @line_numbers = false
        @copy = false
      end

      # True when code is highlighted at build time (no client-side JS).
      def server? : Bool
        @mode == "server"
      end

      # Generate the CSS link tag for highlighting
      def css_tag(cache_bust : String = "") : String
        return "" unless @enabled
        safe_theme = HTML.escape(@theme)
        if @use_cdn
          %(<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/#{safe_theme}.min.css">)
        else
          suffix = Models.cache_bust_suffix(cache_bust)
          %(<link rel="stylesheet" href="/assets/css/highlight/#{safe_theme}.min.css#{suffix}">)
        end
      end

      # Generate the JS script tag for highlighting.
      # Server-side highlighting needs no JavaScript at all — unless the
      # copy button is on, whose (dependency-free) runtime ships either way.
      def js_tag(cache_bust : String = "") : String
        return "" unless @enabled
        return copy ? COPY_SNIPPET : "" if server?
        hljs = if @use_cdn
                 %(<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>\n<script>hljs.highlightAll();</script>)
               else
                 suffix = Models.cache_bust_suffix(cache_bust)
                 %(<script src="/assets/js/highlight.min.js#{suffix}"></script>\n<script>hljs.highlightAll();</script>)
               end
        copy ? "#{hljs}\n#{COPY_SNIPPET}" : hljs
      end

      # Copy-to-clipboard runtime for `pre[data-copy]` blocks: one DOM pass
      # on DOMContentLoaded, appends a button, and copies the code's text on
      # click. An existing `.code-block` (named fences) or `.code-wrapper`
      # parent is reused as the positioning anchor — inserting a new wrapper
      # inside `.code-block` would break its `.code-block > pre` styling —
      # otherwise the <pre> is wrapped in a fresh `.code-wrapper`. Copied
      # text strips the baked-in `.ln` line-number gutter spans (server-mode
      # `linenos`) so pasted code has no number prefixes. Theme-neutral —
      # currentColor only, revealed on hover/focus — and small enough to
      # inline, so no extra request in either highlight mode.
      COPY_SNIPPET = <<-HTML
        <style>.code-wrapper,.code-block{position:relative}.code-copy-btn{position:absolute;top:.4rem;right:.4rem;padding:.25rem .6rem;font:inherit;font-size:.75rem;color:inherit;background:transparent;border:1px solid currentColor;border-radius:.25rem;opacity:0;cursor:pointer;transition:opacity .15s}.code-wrapper:hover .code-copy-btn,.code-block:hover .code-copy-btn,.code-copy-btn:focus-visible,.code-copy-btn.copied{opacity:.75}</style>
        <script>document.addEventListener("DOMContentLoaded",function(){document.querySelectorAll("pre[data-copy]").forEach(function(pre){var w=pre.parentNode;var l=w.classList;if(!l||!(l.contains("code-wrapper")||l.contains("code-block"))){w=document.createElement("div");w.className="code-wrapper";pre.parentNode.insertBefore(w,pre);w.appendChild(pre);}var b=document.createElement("button");b.type="button";b.className="code-copy-btn";b.textContent="Copy";b.setAttribute("aria-label","Copy code");b.addEventListener("click",function(){var c=pre.querySelector("code");var t;if(c){var k=c.cloneNode(true);k.querySelectorAll("span.ln").forEach(function(n){n.remove();});t=k.textContent;}else{t=pre.textContent;}navigator.clipboard.writeText(t).then(function(){b.classList.add("copied");b.textContent="Copied!";setTimeout(function(){b.classList.remove("copied");b.textContent="Copy";},2000);});});w.appendChild(b);});});</script>
        HTML

      # Generate both CSS and JS tags
      def tags(cache_bust : String = "") : String
        return "" unless @enabled
        js = js_tag(cache_bust)
        js.empty? ? css_tag(cache_bust) : "#{css_tag(cache_bust)}\n#{js}"
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_highlight(config : Config)
        return unless s = config.raw["highlight"]?.try(&.as_h?)

        config.highlight.enabled = bool_value(s["enabled"]?, config.highlight.enabled)
        config.highlight.theme = s["theme"]?.try(&.as_s?) || config.highlight.theme
        config.highlight.use_cdn = bool_value(s["use_cdn"]?, config.highlight.use_cdn)
        config.highlight.line_numbers = bool_value(s["line_numbers"]?, config.highlight.line_numbers)
        config.highlight.copy = bool_value(s["copy"]?, config.highlight.copy)
        if mode = s["mode"]?.try(&.as_s?)
          if mode == "client" || mode == "server"
            config.highlight.mode = mode
          else
            Logger.warn "Unknown highlight.mode '#{mode}' — expected \"client\" or \"server\". Using \"server\"."
          end
        end
      end
    end
  end
end
