# Single source of truth for the "Hwaro Ember" design-token system shared by
# every init scaffold.
#
# One warm identity, both schemes: every color token is a `light-dark()` pair
# resolved by the page's `color-scheme`, so all scaffolds (including the
# default `simple`) adapt to the OS scheme automatically. The `*-dark`
# scaffolds are presets that force `color-scheme: dark` via `forced_dark_css`
# instead of shipping a second stylesheet.
#
# Rules of the system:
#   * Scaffold component CSS never hardcodes a color — everything goes
#     through these tokens (a hygiene spec enforces this).
#   * Layout tokens (--header-h, --sidebar-w, --content-max-w, --bg-sidebar,
#     radius overrides) are per-scaffold and injected through `root_block`'s
#     `layout` hook.
#   * Emission is deterministic: pure string builders, no state.
module Hwaro
  module Services
    module Scaffolds
      module DesignTokens
        # Exposed for specs and tooling that need the brand anchors.
        PRIMARY_LIGHT = "#b35454"
        PRIMARY_DARK  = "#ec7a66"
        BG_LIGHT      = "#faf7f2"
        BG_DARK       = "#0f0f0e"

        # The full shared `:root` prelude: color tokens (light-dark pairs),
        # the fluid type scale, the 8px spacing scale, shape/depth/motion
        # tokens, and the font stacks — plus a static-light fallback for
        # browsers that predate `light-dark()` (Baseline 2024). `layout`
        # lines are appended inside `:root` so scaffolds add their own
        # geometry without re-declaring the vocabulary.
        def self.root_block(layout : String = "") : String
          layout_lines = layout.strip.empty? ? "" : "\n  /* Layout (scaffold-specific) */\n#{layout.strip.lines.join("\n") { |l| "  #{l.strip}" }}\n"
          <<-CSS
            :root {
              /* ── Hwaro Ember tokens ─────────────────────────────────────
                 One warm identity, both schemes. Colors are light-dark()
                 pairs resolved by color-scheme; *-dark scaffolds force
                 `color-scheme: dark` at the end of the sheet. Browsers
                 without light-dark() (pre-2024) get the static light
                 palette from the fallback block below. */
              color-scheme: light dark;

              /* Accent — the single ember. */
              --primary:        light-dark(#b35454, #ec7a66);
              --primary-strong: light-dark(#8f4040, #f39683);
              --primary-tint:   color-mix(in srgb, var(--primary) 8%, transparent);
              --selection:      color-mix(in srgb, var(--primary) 22%, transparent);

              /* Ember rule — the one mark every scaffold shares. */
              --rule-from: light-dark(#c46262, #f39683);
              --rule-to:   light-dark(#8f4040, #cc5d4b);

              /* Ink — a three-step ramp. */
              --heading:        light-dark(#241f1a, #f5f2ed);
              --text:           light-dark(#2a241f, #dedad3);
              --text-secondary: light-dark(#5c5248, #a7a199);
              --text-muted:     light-dark(#6f6358, #7d776e);

              /* Surfaces & edges. */
              --bg:            light-dark(#faf7f2, #0f0f0e);
              --bg-subtle:     light-dark(#f1eae0, #1a1917);
              --bg-code:       light-dark(#f1eae0, #1e1c19);
              --border:        light-dark(#e4dacd, #2b2926);
              --border-subtle: light-dark(#efe8dd, #201e1c);
              --edge:  color-mix(in srgb, var(--text) 8%, transparent);
              --glass: color-mix(in srgb, var(--bg) 85%, transparent);
              --scrim: light-dark(rgba(0, 0, 0, 0.4), rgba(0, 0, 0, 0.6));

              /* Support hues (info boxes only — the accent stays singular). */
              --warn: light-dark(#b07d2e, #d9a45a);
              --ok:   light-dark(#5e8c61, #8fb491);

              /* Syntax (hljs classes; client and server highlighting). */
              --code-comment:  light-dark(#a1907c, #8a8073);
              --code-keyword:  light-dark(#b03a2e, #f0846f);
              --code-string:   light-dark(#5f7032, #b7c06a);
              --code-number:   light-dark(#9a6a14, #e8a83f);
              --code-func:     light-dark(#2f6a5a, #8ec5a3);
              --code-type:     light-dark(#b0641c, #e6914f);
              --code-variable: light-dark(#8a4a3a, #e8b0a0);
              --code-attr:     light-dark(#45617a, #93b5c8);
              --code-symbol:   light-dark(#8a4368, #d79bb8);

              /* Type scale — minor third (1.2), fluid. */
              --step--1: clamp(0.83rem, 0.81rem + 0.11vw, 0.89rem);
              --step-0:  clamp(1rem, 0.96rem + 0.22vw, 1.125rem);
              --step-1:  clamp(1.2rem, 1.13rem + 0.35vw, 1.4rem);
              --step-2:  clamp(1.44rem, 1.32rem + 0.61vw, 1.78rem);
              --step-3:  clamp(1.73rem, 1.53rem + 0.98vw, 2.28rem);
              --step-4:  clamp(2.07rem, 1.77rem + 1.52vw, 2.92rem);

              /* Space — 8px rhythm. */
              --space-1: 0.25rem;
              --space-2: 0.5rem;
              --space-3: 0.75rem;
              --space-4: 1rem;
              --space-5: 1.5rem;
              --space-6: 2.5rem;
              --space-7: 4rem;
              --space-8: 6rem;

              /* Shape, depth, motion, measure. */
              --measure: 68ch;
              --radius: 10px;
              --radius-sm: 6px;
              --shadow-sm: 0 1px 2px light-dark(rgba(42, 36, 31, 0.05), rgba(0, 0, 0, 0.3));
              --shadow:    0 2px 8px light-dark(rgba(42, 36, 31, 0.08), rgba(0, 0, 0, 0.4));
              --shadow-lg: 0 16px 70px light-dark(rgba(42, 36, 31, 0.18), rgba(0, 0, 0, 0.5));
              --transition: 0.15s ease;

              /* Faces. */
              --font-serif: "Charter", "Bitstream Charter", "Iowan Old Style", "Palatino Linotype", Georgia, "Noto Serif KR", serif;
              --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              --font-mono: ui-monospace, "SF Mono", "Cascadia Code", Menlo, Consolas, monospace;#{layout_lines}
            }

            /* Pre-light-dark() browsers: pin the static light palette so the
               site stays fully styled (they would otherwise collapse to UA
               defaults — var() with an invalid value is not a cascade
               fallback). A *-dark site renders light there: readable and
               on-brand. */
            @supports not (color: light-dark(#000, #fff)) {
              :root {
                --primary: #b35454;
                --primary-strong: #8f4040;
                --primary-tint: rgba(179, 84, 84, 0.08);
                --selection: rgba(179, 84, 84, 0.22);
                --rule-from: #c46262;
                --rule-to: #8f4040;
                --heading: #241f1a;
                --text: #2a241f;
                --text-secondary: #5c5248;
                --text-muted: #6f6358;
                --bg: #faf7f2;
                --bg-subtle: #f1eae0;
                --bg-code: #f1eae0;
                --border: #e4dacd;
                --border-subtle: #efe8dd;
                --edge: rgba(42, 36, 31, 0.08);
                --glass: rgba(250, 247, 242, 0.85);
                --scrim: rgba(0, 0, 0, 0.4);
                --warn: #b07d2e;
                --ok: #5e8c61;
                --code-comment: #a1907c;
                --code-keyword: #b03a2e;
                --code-string: #5f7032;
                --code-number: #9a6a14;
                --code-func: #2f6a5a;
                --code-type: #b0641c;
                --code-variable: #8a4a3a;
                --code-attr: #45617a;
                --code-symbol: #8a4368;
                --shadow-sm: 0 1px 2px rgba(42, 36, 31, 0.05);
                --shadow: 0 2px 8px rgba(42, 36, 31, 0.08);
                --shadow-lg: 0 16px 70px rgba(42, 36, 31, 0.18);
              }
            }
            CSS
        end

        # The ember-warm syntax-highlight theme, colored entirely through the
        # `--code-*` tokens so it follows the resolved scheme in every
        # highlight mode (client CDN, client self-hosted, and server-side
        # Tartrazine output — all emit the same hljs classes). `.hljs` itself
        # stays transparent so code sits on the `--bg-code` well set by `pre`.
        def self.highlight_css : String
          <<-CSS
            /* Syntax highlighting — ember-warm, token-driven (recolor via --code-*). */
            .hljs-comment, .hljs-quote { color: var(--code-comment); font-style: italic; }
            .hljs-keyword, .hljs-selector-tag, .hljs-literal, .hljs-section, .hljs-doctag { color: var(--code-keyword); }
            .hljs-string, .hljs-regexp, .hljs-addition, .hljs-meta .hljs-string { color: var(--code-string); }
            .hljs-number, .hljs-built_in, .hljs-builtin-name, .hljs-bullet { color: var(--code-number); }
            .hljs-title, .hljs-title.function_, .hljs-section .hljs-title { color: var(--code-func); }
            .hljs-type, .hljs-class .hljs-title, .hljs-title.class_, .hljs-tag { color: var(--code-type); }
            .hljs-attr, .hljs-attribute, .hljs-variable, .hljs-template-variable, .hljs-name { color: var(--code-variable); }
            .hljs-selector-id, .hljs-selector-class, .hljs-selector-attr { color: var(--code-attr); }
            .hljs-symbol, .hljs-link, .hljs-meta, .hljs-params { color: var(--code-symbol); }
            .hljs-deletion { color: var(--code-keyword); }
            .hljs-emphasis { font-style: italic; }
            .hljs-strong { font-weight: 700; }
            CSS
        end

        # Appended as the last rule of a `*-dark` scaffold's sheet: a
        # later-in-sheet, same-specificity `color-scheme` declaration wins,
        # flipping every light-dark() token above to its dark side.
        def self.forced_dark_css : String
          <<-CSS
            /* ── Forced dark preset ──────────────────────────────────────
               This scaffold pins the dark side of every light-dark() token.
               Delete this rule to restore automatic OS-scheme switching. */
            :root { color-scheme: dark; }
            CSS
        end

        # The pair of `theme-color` metas that keep the browser chrome in
        # step with the resolved scheme on mobile.
        def self.theme_color_meta : String
          <<-HTML
            <meta name="theme-color" media="(prefers-color-scheme: light)" content="#{BG_LIGHT}">
            <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#{BG_DARK}">
            HTML
        end
      end
    end
  end
end
