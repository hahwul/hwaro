# Markdown extensions — external link rel/target attributes.
#
# One file per `# --- X ---` pass of the pre/post-processing pipeline; the
# pass ORDER is fixed in ../markdown_extensions.cr (`preprocess` /
# `postprocess`). Parts only reopen the module: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Content
    module Processors
      module MarkdownExtensions
        # --- External links ---
        # Site-wide policy for absolute http(s) links (Zola parity):
        # target="_blank" (+ rel="noopener", Zola's pairing), rel="nofollow",
        # rel="noreferrer". Applied as an HTML pass because <a> tags come
        # from four producers (markd, InlineMarkdown table cells/definitions,
        # footnote sections, render-link hooks) — only postprocess sees them
        # all. Merge semantics, not override: an anchor that already carries
        # target= keeps it, and rel tokens are deduped into an existing
        # rel="…" — so a render-link hook's explicit choices win. Applies to
        # every absolute http(s) href, including ones pointing at the site's
        # own domain (documented; matches Zola). Code blocks are immune:
        # markd entity-escapes `<a` inside them.
        EXTERNAL_ANCHOR_RE = /<a\s((?:[^>"']|"[^"]*"|'[^']*')*)>/i
        EXTERNAL_HREF_RE   = /(?<![\w-])href\s*=\s*"https?:\/\//i
        EXISTING_TARGET_RE = /(?<![\w-])target\s*=/i
        EXISTING_REL_RE    = /(?<![\w-])rel\s*=\s*"([^"]*)"/i

        def postprocess_external_links(html : String, config : Models::MarkdownConfig) : String
          target_blank = config.external_links_target_blank
          rel_tokens = [] of String
          rel_tokens << "noopener" if target_blank
          rel_tokens << "nofollow" if config.external_links_no_follow
          rel_tokens << "noreferrer" if config.external_links_no_referrer
          # Every active flag contributes a rel token, so empty ⇒ policy off.
          return html if rel_tokens.empty?
          # Markd keeps author scheme case (`HTTPS://…`); the rewrite regex is
          # already /i, so the early-out must not require lowercase `http`.
          return html unless html.includes?(%(href="http)) || html.includes?(%(href="HTTP))

          html.gsub(EXTERNAL_ANCHOR_RE) do |match|
            attrs = $1
            next match unless EXTERNAL_HREF_RE.matches?(attrs)

            new_attrs = attrs
            if target_blank && !EXISTING_TARGET_RE.matches?(new_attrs)
              new_attrs = %(#{new_attrs.rstrip} target="_blank")
            end
            if rel_match = new_attrs.match(EXISTING_REL_RE)
              existing = rel_match[1].split
              merged = existing + rel_tokens.reject { |token| existing.includes?(token) }
              # `backreferences: false`: `merged` starts with the author's own
              # rel tokens, and `String#sub(Regex, String)` expands `\0`-`\9` /
              # `\k<name>` inside the REPLACEMENT. Without the flag a literal
              # `rel="a\1b"` would splice the match back in, and `rel="\k<g>"`
              # would raise `IndexError` and abort the build.
              new_attrs = new_attrs.sub(EXISTING_REL_RE, %(rel="#{merged.join(' ')}"), backreferences: false)
            else
              new_attrs = %(#{new_attrs.rstrip} rel="#{rel_tokens.join(' ')}")
            end
            "<a #{new_attrs}>"
          end
        end
      end
    end
  end
end
