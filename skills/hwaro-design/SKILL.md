---
name: hwaro-design
description: >-
  Use when designing or restyling a Hwaro site — choosing a visual direction,
  customizing templates and CSS, building or retheming a theme, picking
  typography and color, or improving an existing layout. Read the brief, declare
  a Design Read and set the three dials, interview only when intent is genuinely
  ambiguous, then produce distinctive, production-grade design within Hwaro's
  Crinja template + CSS-variable token system — under a strict anti-slop
  discipline and a mechanical pre-flight check. Pair with the `hwaro` skill,
  which covers operating the CLI itself.
---

# Hwaro Design

Your job is to design Hwaro sites that look **intentional, distinctive, and
genuinely good** — and that reflect *this user's* taste, not a generic default.
A static site generator makes the plumbing trivial; the design is where the site
either feels considered or feels like every other template. Aim for the former.

This skill assumes the project is a Hwaro site (config.toml + `templates/` +
`static/`). For scaffolding, building, and serving, use the **`hwaro`** skill;
iterate with `hwaro serve` (live reload) so the user sees changes instantly.

Every rule below is **contextual** — none fires automatically. First read the
brief, then pull only what fits. But the bans in Section 9 and the Pre-Flight
Check in Section 12 are hard filters: output that violates them is not done.

---

## 0. The Design Read — read the room before anything else

Before touching code or setting dials, **infer what the user actually wants**.
Most AI design output is bad because the model jumps to a default aesthetic
instead of reading the room.

### 0.A Read these signals first

1. **Site kind** — blog / docs / portfolio (dev, designer, studio) / landing
   (product, event, agency) / book / shop-adjacent brochure / redesign
   (preserve vs. overhaul).
2. **Vibe words** the user used — "minimalist", "calm", "Linear-style",
   "Awwwards", "brutalist", "premium consumer", "Apple-y", "playful",
   "serious B2B", "editorial", "glassy", "dark tech", "warm-handcrafted".
3. **Reference signals** — URLs they linked, screenshots they pasted, products
   or brands they named.
4. **Audience** — recruiters scanning a portfolio vs. developers reading docs
   vs. design-conscious consumers. The audience picks the aesthetic, not your
   taste.
5. **Brand assets that already exist** — logo, color, type, photography. For
   redesigns these are starting material, not optional input (Section 10).
6. **Quiet constraints** — accessibility-first audiences, public-sector,
   regulated industries, kids' content, CJK-primary readership (keep the CJK
   font fallbacks — see Section 4.1). These constraints OVERRIDE aesthetic
   preference.

### 0.B Declare a one-line Design Read before generating

Before any code, state in one line: **"Reading this as: \<site kind> for
\<audience>, with a \<vibe> language, leaning toward \<aesthetic family>"** —
followed by the three dial values (Section 1) and why.

Example reads:

- *"Reading this as: developer blog for peers, with a calm technical-editorial
  language, leaning toward mono-accented minimalism. Dials: 5 / 3 / 4."*
- *"Reading this as: product landing for design-conscious indie devs, with a
  confident dark-tech language, leaning toward near-black canvas + single
  electric accent. Dials: 7 / 6 / 3."*
- *"Reading this as: redesign-preserve of an existing docs site — extract the
  current tokens first, evolve typography and rhythm, keep the IA. Dials: match
  existing."*

### 0.C Question policy — hybrid

- **If you can confidently infer the direction from the brief, conversation, or
  the existing site: do not ask.** Declare the Design Read and proceed. A
  confident direction the user can react to beats an interview they didn't want.
- **If the read genuinely diverges** (e.g. "Linear-clean or
  Awwwards-experimental?" would produce different sites), ask a **short round —
  1–2 focused questions**, not a survey. Use `AskUserQuestion` when available:
  2–4 concrete options per question with short descriptions, and lean on its
  **option previews** — a token-value block or a small ASCII layout sketch per
  option beats adjectives; people pick a palette they can *see*.
- **Run a full interview only when the user asks to explore taste** ("interview
  me", "help me figure out what I want") or a greenfield brief gives you nothing
  to read. Then cover, in order, stopping once you can commit: purpose &
  audience · personality + 1–3 reference sites · color mood incl. light/dark ·
  type feel · density & layout · motion appetite · constraints.
- Either way, for any substantial engagement **play the brief back** in 4–6
  lines ("Warm editorial blog: cream paper background, single rust accent,
  Charter-style serif headings over a clean sans body, generous whitespace,
  motion limited to gentle link transitions") and confirm before building big.
  The brief is the contract you design against.
- If a confirmed brief already exists earlier in the conversation, don't
  re-interview — proceed from it, and only revisit taste if the user's
  direction changed.

### 0.D Anti-Default Discipline

Do not default to: AI-purple gradients, centered hero over dark mesh, three
equal feature cards with an emoji each, generic glassmorphism on everything,
infinite-loop micro-animations, system-font-with-no-personality — and, the
Hwaro-specific one, **shipping the ember scaffold palette unchanged and calling
it a design**. The ember tokens are a *starting vocabulary*, not the answer to
a brief. Reach past the defaults deliberately, based on the Design Read.

---

## 1. The Three Dials

After the Design Read, set three dials. Every layout, motion, and density
decision below is gated by these.

- **`DESIGN_VARIANCE`** — 1 = perfect symmetry, 10 = artsy chaos
- **`MOTION_INTENSITY`** — 1 = static, 10 = cinematic choreography
- **`VISUAL_DENSITY`** — 1 = art gallery / airy, 10 = cockpit / packed data

State the values in the Design Read. Never silently assume a baseline —
reason them from the brief. Overrides happen conversationally ("crank the
motion to 8").

### 1.A Dial inference (Design Read → dial values)

| Signal | VARIANCE | MOTION | DENSITY |
|---|---|---|---|
| "minimalist / clean / calm / editorial / Linear-style" | 5–6 | 3–4 | 2–3 |
| "premium consumer / Apple-y / luxury / brand" | 7–8 | 5–7 | 3–4 |
| "playful / wild / Awwwards / experimental / agency" | 9–10 | 8–10 | 3–4 |
| Blog (personal / technical) | 5–6 | 3–4 | 3–4 |
| Docs / book | 3–4 | 2–3 | 4–6 |
| Landing / portfolio (default) | 7–9 | 5–7 | 3–5 |
| "trust-first / public-sector / accessibility-critical" | 3–4 | 2–3 | 4–5 |
| Redesign — preserve | match existing | +1 | match existing |
| Redesign — overhaul | +2 | +2 | match existing |

### 1.B Dial definitions (technical reference, plain-CSS terms)

**DESIGN_VARIANCE**
- **1–3 (Predictable):** symmetrical grid (equal `fr` units), equal paddings,
  centered alignment. Right for docs, books, trust-first.
- **4–7 (Offset):** negative-margin overlaps, varied image aspect ratios (4:3
  next to 16:9), left-aligned headers over centered content blocks.
- **8–10 (Asymmetric):** masonry, fractional grids
  (`grid-template-columns: 2fr 1fr 1fr`), massive deliberate empty zones
  (`padding-inline-start: 20vw`).
- **MOBILE OVERRIDE:** for levels 4–10, asymmetric layouts MUST collapse to a
  strict single column below 768px. Declare the collapse in the same rule
  block, not "it'll probably reflow."

**MOTION_INTENSITY**
- **1–3 (Static):** `:hover` / `:active` / `:focus-visible` transitions only.
- **4–7 (Fluid CSS):** `transition: … 0.3s var(--ease-out)`,
  `animation-delay` cascades for load-ins, transform/opacity only.
- **8–10 (Choreography):** scroll-driven reveals via CSS
  `animation-timeline: view()` (behind `@supports`) or an IntersectionObserver
  (Section 7). **`window.addEventListener("scroll", …)` is a hard ban**, not a
  prefer-not.

**VISUAL_DENSITY**
- **1–3 (Art gallery):** huge section gaps (8–12rem), few elements, expensive
  whitespace.
- **4–7 (Daily site):** standard rhythm (4–6rem section padding) — the
  `--space-*` scale as-shipped.
- **8–10 (Cockpit):** tight paddings, no card boxes, hairlines separate data,
  `--font-mono` for all numbers.

---

## 2. How design lives in a Hwaro site

Know the actual surfaces you can touch — this is what makes the design *real*
and not just advice.

### Templates (Crinja / Jinja2-compatible) — the structure

Under `templates/`. Hwaro supports both `{% extends "base.html" %}`
inheritance (filling `{% block content %}`) and `{% include %}` partial
composition. The built-in scaffolds all use **includes**: `page.html` /
`section.html` (and `index.html`, `post.html`, `archives.html` in `blog`)
start with `{% include "header.html" %}` and end with
`{% include "footer.html" %}`, with partials under `partials/` (`nav.html`,
`sidebar.html`, `search.html`, …) plus `taxonomy*.html` and `404.html`. Open
the project's `templates/` before editing; a third-party theme may use
inheritance instead. Layout changes (what wraps what) happen here; *look*
(color, type, spacing) happens in CSS. Keep markup semantic and class-driven
so the CSS can do the work.

**Internal URLs must carry the base URL.** The scaffolds write every
site-internal href/src as `{{ base_url }}{{ page.url }}`,
`{{ base_url }}{{ lang_prefix }}/about/`, `{{ base_url }}/css/style.css`
(`url_for(path=…)`, `| relative_url` and `asset(name=…)` are equivalent) —
never a bare `/about/`. Keep that pattern in every template you author, or the
site 404s the moment it's deployed under a subpath (GitHub Pages project
sites).

### CSS delivery — three options, pick deliberately

1. **Inlined `<style>`** — the `simple` scaffold ships its CSS in a `<style>`
   block inside `header.html`: zero extra requests, great for small sites; edit
   that block directly. (`blog` / `book` / `docs` instead ship an external
   `static/css/style.css`; `bare` ships *no* CSS at all, so you bring your own.)
2. **Static stylesheet + `[auto_includes]`** — drop files in `static/assets/css/`
   (and `…/js`) and emit `{{ auto_includes_css }}` / `{{ auto_includes_js }}` in
   your head/body. Good when CSS grows past "one block."
3. **`[assets]` pipeline** — declare bundles in `config.toml`, reference with
   `{{ asset(name='main.css') }}`; you get concatenation, minification, and
   content-hash fingerprinting (cache busting) for free.

Template output is never autoescaped, so `{{ content }}`,
`{{ auto_includes_css }}` and friends need no `| safe` (the docs add it as a
harmless convention; keep it if you see it).

> **SCSS is built in; Tailwind and component frameworks are not.**
> `[sass] enabled = true` compiles `.scss` with a pure-Crystal compiler that
> tracks dart-sass closely: variables, nesting, `@use`/`@forward`/`@import`,
> mixins, `@function`, control flow (`@if`/`@each`/`@for`/`@while`), unit
> arithmetic, and the `math`/`color`/`list`/`map`/`string`/`selector` modules
> (Bootstrap and Bulma compile). Not supported: the indented `.sass` syntax,
> source maps, `@forward … with (…)`, compound units, `math.random`. Still,
> default to modern plain CSS (custom properties, nesting, `color-mix()`,
> `clamp()`, `light-dark()`); reach for `[sass]` when the brief or an existing
> codebase calls for it, and run Tailwind/PostCSS via **build hooks**
> (`[build] hooks.pre`), pointing Hwaro at the compiled output. When a brief
> names an aesthetic (glass, bento, brutalist, editorial, dark tech, aurora),
> that's a CSS language you build honestly by hand — there is no package for it.

### Design tokens are your single source of truth

Every styled scaffold (`simple`, `blog`, `docs`, `book`) themes itself through
one shared **"Hwaro Ember"** set of CSS custom properties in `:root`, emitted
from `DesignTokens.root_block` (`src/services/scaffolds/design_tokens.cr` in the
Hwaro repo). Every color token is a `light-dark(light, dark)` pair under
`color-scheme: light dark`, so the site follows the reader's OS scheme with no
extra CSS. **Read the exact values from the project itself** — the `:root`
block at the top of `static/css/style.css` (or of the `<style>` in
`header.html` for `simple`) — rather than from memory; they evolve between
releases. The vocabulary, by role:

| Role | Tokens |
|---|---|
| Accent (the single ember) | `--primary`, `--primary-strong` (hover/active), `--primary-tint`, `--selection` |
| Signature mark | `--rule-from`, `--rule-to`, `--spark` (135° gradient of the two) |
| Ink ramp (never pure black/white) | `--heading`, `--text`, `--text-secondary`, `--text-muted` |
| Surfaces & edges | `--bg`, `--bg-subtle`, `--bg-raised`, `--bg-code`, `--border`, `--border-subtle`, `--edge`, `--glass`, `--glass-filter`, `--scrim` |
| Support hues (info boxes only) | `--warn`, `--ok` |
| Syntax (read by the `.hljs-*` rules) | `--code-comment`, `-keyword`, `-string`, `-number`, `-func`, `-type`, `-variable`, `-attr`, `-symbol` |
| Type scale (minor third, fluid `clamp()`) | `--step--1` … `--step-5` |
| Space (8px rhythm) | `--space-1` … `--space-8` (0.25rem → 6rem) |
| Shape, depth, motion, measure | `--radius` (12px), `--radius-sm` (8px), `--shadow-sm`, `--shadow`, `--shadow-lg` (tinted, not black), `--ease-out` (`cubic-bezier(0.16, 1, 0.3, 1)`), `--transition` (0.15s), `--transition-slow` (0.45s), `--measure` (68ch) |
| Faces | `--font-serif` (Charter → embedded OFL Charis SIL → … → `"Noto Serif KR"`), `--font-sans`, `--font-mono` |

Per-scaffold layout tokens (`--header-h`, `--sidebar-w`, `--content-max-w`,
`--bg-sidebar`, radius overrides) are appended to the same `:root`. An
`@supports not (color: light-dark(#000, #fff))` block pins the static light
palette for pre-2024 browsers, so they stay readable and on-brand.

**Retheme by rewriting token values, not by adding parallel systems.** The
scale, rhythm, radii, shadows and motion tokens already exist — don't
re-create them under new names; override their values (a different ratio, a
denser rhythm) and build every component against them. Never hardcode a raw
color in a rule: reach for the existing pair, or `color-mix()` off one.

```css
/* A custom retheme = override the light-dark() pairs in :root.
   Always set BOTH sides — a light-only override ships a broken dark scheme. */
:root {
  --primary:        light-dark(#3a6ea5, #7fb2e5);
  --primary-strong: light-dark(#2c567f, #a3c9ee);
  --bg:             light-dark(#f7f9fb, #101418);
  /* …continue through the ink ramp, surfaces, and --code-* slots… */
}
```

> **Dark mode and the theme switcher already ship — don't re-plumb them.**
> - The styled scaffolds include a **theme switcher** (`.theme-toggle` in the
>   nav, inline script in `footer.html`) that cycles auto → light → dark, sets
>   `data-theme` on `<html>`, and remembers the choice in `localStorage`
>   (`hwaro-theme`). `:root[data-theme="light"|"dark"] { color-scheme: … }`
>   at the end of the token block does the rest. `bare` has none.
> - **A custom retheme** only touches the token pairs; the switcher keeps
>   working because it flips `color-scheme`, not colors.
> - **Locking one scheme** (a dark-only brand) = set `color-scheme: dark` on
>   `:root` *and* remove the switcher markup and script; otherwise the toggle
>   still flips the page back to light.
> - When editing scaffold *source* in the Hwaro repo, the hygiene spec
>   (`spec/unit/services/scaffolds/scaffold_token_hygiene_spec.cr`) fails on
>   any hardcoded color outside the token definitions.

### Code blocks are a design surface

The scaffolds' `.hljs-*` rules read entirely from the nine `--code-*` tokens,
in every highlight mode (server-side Tartrazine and client highlight.js emit
the same classes) — so recoloring syntax means editing those `light-dark()`
pairs in `:root`, not touching the `.hljs-*` rules. Tie them to your palette
(e.g. keywords near your accent) for cohesion; both schemes come along
automatically.

---

## 3. The quality bar

Production-grade design is a stack of deliberate decisions. Hit every layer.

- **A point of view.** Pick one organizing idea (Swiss/grid precision, warm
  editorial, brutalist mono, retro terminal, glassy modern, dark tech…) and let
  it govern every choice. Coherence reads as quality.
- **Typography does the heavy lifting.** A deliberate pairing (or one great
  family with real weight range), a modular scale, tuned line-height and
  measure. Details in Section 4.1.
- **Color with intent.** One dominant surface family, considered neutrals, ONE
  confident accent. Details in Section 4.2.
- **A spatial system.** One spacing scale used everywhere. Consistent rhythm,
  alignment, and generous negative space are what make a layout feel composed.
- **Clear hierarchy & a focal point.** Every screen has an obvious entry point
  and an unambiguous reading order — established by size, weight, color, and
  space, not boxes everywhere.
- **Texture & detail, used with restraint.** Hairline borders, a *single*
  considered shadow elevation, a subtle gradient or grain, one small recurring
  motif (the scaffolds use one short accent rule under the page title). Detail
  signals care; clutter signals the opposite.
- **Motion with purpose.** Section 7. Always honor `prefers-reduced-motion`.
- **Responsive by construction.** Design the small screen and the large screen,
  not just a desktop that shrinks. Fluid type/space via `clamp()`, real touch
  targets.
- **Accessibility is part of "good," not a checkbox.** Semantic HTML, visible
  `:focus-visible`, a skip link, alt text, sufficient contrast, logical heading
  order.

---

## 4. Design engineering directives (bias correction)

LLMs default to clichés. Override these defaults proactively. Each rule has a
context-aware override path.

### 4.1 Typography

- **Display / headlines:** large steps of the scale (`--step-3`/`--step-4`),
  `letter-spacing: -0.02em`-ish tightening, `line-height` near 1–1.15,
  `text-wrap: balance`.
- **Body:** `--step-0`, `line-height` 1.5–1.7, `max-width: var(--measure)`
  (60–75ch), `text-wrap: pretty` on paragraphs.
- **Fonts are self-hosted.** `@font-face` + `font-display: swap`, subset files,
  limit families/weights — fonts are usually the biggest perf cost of a
  "designed" site. Never `<link>` Google Fonts in production. The scaffolds
  embed Charter via OFL Charis SIL so headings render the same off-Apple.
- **Keep the CJK fallbacks.** The shipped stacks include `"Noto Serif KR"`-class
  fallbacks; if the audience reads CJK, stripping them breaks the design where
  it matters most. (This also applies to OG images — CJK-capable font chains.)

- **SERIF DISCIPLINE.** The ember scaffolds ship Charter serif headings, and
  for *content* sites (blog, docs, book — genuinely editorial surfaces) that
  default is legitimate. But when the brief is a **landing page, portfolio,
  agency, or product site**, serif is **very discouraged as the default
  reach**. "It feels creative / premium / editorial" is NOT a reason. Serif is
  acceptable only when the brand brief literally names a serif, or the
  aesthetic family is genuinely editorial / luxury / publication / heritage AND
  you can articulate why this serif fits this brand. Otherwise default to a
  characterful sans display. **Specifically banned as default reaches:
  Fraunces and Instrument Serif** (the two LLM-favorite display serifs). If a
  serif is justified, don't reuse the same one across consecutive projects.
- **EMPHASIS RULE.** To emphasize a word inside a headline, use *italic* or
  **bold of the SAME family**. Do not inject a serif word into a sans headline
  (or vice versa) for visual interest — mixed-family emphasis is amateur.
- **ITALIC DESCENDER CLEARANCE.** Italic display words containing `y g j p q`
  get clipped at `line-height: 1`. Use ≥ 1.1 and reserve a few px of
  padding-bottom on the wrapper. Audit every italic display word before
  shipping.
- **No oversized H1s that just scream.** Control hierarchy with weight, color,
  and space, not raw scale alone.

### 4.2 Color calibration

- **Max 1 accent color**, saturation < 80% by default. Neutrals are never pure
  `#000`/`#fff` (the ember ink ramp is the model). Use `color-mix()` for
  tints/states instead of inventing new hex values.
- **THE LILA RULE.** The "AI purple/blue glow" aesthetic is banned as a
  default. No automatic purple button glows, no random neon gradients. Neutral
  bases with one high-contrast singular accent (emerald, electric blue, deep
  rose, burnt orange…). *Override:* if the brand explicitly is purple, embrace
  it — with a consistent palette and restrained gradients, not gradient slop.
- **COLOR CONSISTENCY LOCK.** Once the accent is chosen, it is THE accent for
  the whole site. A warm-gray site does not get a blue CTA in the footer; a
  rose-accented site does not get a teal badge. In Hwaro terms: **everything
  reads from `--primary` / `--primary-strong`** — if you're tempted to add a
  second accent variable, you're breaking the lock.
- **One palette per site.** Don't fluctuate between warm and cool grays.
- **PREMIUM-CONSUMER PALETTE BAN.** For premium-consumer briefs (cookware,
  wellness, artisan goods, luxury, DTC home goods) the LLM default is warm
  cream/beige surfaces + brass/clay/oxblood accents + espresso near-black text.
  **Note: the ember scaffold palette IS this family** (warm paper background,
  rust accent, warm ink). That's fine as Hwaro's out-of-the-box identity — but
  reaching for it (or just keeping it) as *the design* for a premium-consumer
  client brief is the lazy move. Rotate to a genuinely different family:
  - **Cold luxury:** silver-gray + chrome + smoke
  - **Forest:** deep green + bone + amber accent
  - **Black and tan:** true off-black + warm tan, sharp contrast, no beige
  - **Cobalt + cream:** saturated blue against a single neutral
  - **Terracotta + slate:** warm rust against cool gray
  - **Monochrome + one pop:** off-white + off-black + one bright accent
  *Override:* warm-craft beige is acceptable when the brand brief explicitly
  names those colors or the identity is genuinely vintage/artisan AND you can
  say why. Defaulting to it because "this is a cookware brief" is banned.
- **Both sides, always.** Every custom color is a `light-dark()` pair with both
  sides supplied (Section 2). A light-only override ships a broken dark scheme.

### 4.3 Layout diversification

- **ANTI-CENTER BIAS.** Centered hero / H1 sections are avoided when
  `DESIGN_VARIANCE > 4`. Prefer split (50/50), left-aligned content with
  right-aligned asset, asymmetric whitespace, or a pinned structure.
  *Override:* centered is fine for editorial / manifesto briefs where the
  message itself is the design — and for docs/book content pages, which are
  reading surfaces, not compositions.

### 4.4 Materiality, shadows, cards

- Use cards ONLY when elevation communicates real hierarchy. Otherwise group
  with a top border, row dividers used sparsely, or negative space.
- When a shadow is used, tint it toward the background hue (the ember
  `--shadow*` tokens already do this). No pure-black drop shadows on light
  backgrounds.
- For `VISUAL_DENSITY > 7`: generic card containers are banned; data breathes
  in plain layout with hairlines.
- **SHAPE CONSISTENCY LOCK.** One corner-radius system per site — that's what
  `--radius` / `--radius-sm` are for. All-sharp (0), all-soft (12–16px), or
  all-pill for interactive — pick one, or document the mixed rule ("buttons
  pill, cards 16px, inputs 8px") and follow it everywhere. Round buttons in a
  square layout is broken design.

### 4.5 Interactive states

- **Tactile feedback:** on `:active`, a 1px translate or `scale(0.98)` to
  simulate a physical push. Short eased transitions on all interactive
  elements (`var(--transition)`).
- **Visible `:focus-visible`** on every interactive element. A skip link at the
  top of `base.html`/`header.html`.
- **BUTTON CONTRAST CHECK.** Every CTA's text is readable against its own
  background: WCAG AA (4.5:1 body, 3:1 large/UI). White-on-white, ghost
  buttons over photos with no scrim/stroke — banned. Audit every CTA.
- **CTA BUTTON WRAP BAN.** Button text fits on one line at desktop. If a label
  wraps, shorten the label (1–3 words for primary CTAs) or widen the button.
- **NO DUPLICATE CTA INTENT.** "Get in touch" + "Contact us" + "Let's talk" on
  one page = one intent, three labels = fail. Pick ONE label per intent and use
  it everywhere (nav, hero, footer). Same for "View work" / "Browse projects".
- **FORM CONTRAST CHECK.** Inputs, placeholders, focus rings, helper and error
  text all pass WCAG AA against the section background. Label ABOVE input;
  error text below. **No placeholder-as-label. Ever.**

### 4.6 Layout discipline (hard rules — failing any of these is shipping broken work)

- **Hero MUST fit the initial viewport.** Headline ≤ 2 lines on desktop,
  subtext ≤ 20 words AND ≤ 3–4 lines, CTA visible without scroll. If the copy
  is too long, cut copy or reduce scale — never let the hero overflow.
  Use `min-height: 100dvh` for full-height heroes, never `100vh` (iOS address
  bar jump).
- **Hero font-scale discipline.** Plan font size and asset size *together*.
  `--step-4` territory only when the headline is 3–5 words; a 4-line hero
  headline is always a font-size error, never a copy-length error.
- **HERO TOP PADDING CAP.** Max ~6rem top padding at desktop. If the hero needs
  more breathing room, increase font scale or asset size, not top padding.
- **HERO STACK DISCIPLINE (max 4 text elements):** eyebrow OR brand strip (or
  neither) · headline · subtext · CTAs (1 primary + max 1 secondary). BANNED in
  the hero: tiny tagline below CTAs, trust micro-strip, pricing teaser, feature
  bullet list, social-proof avatar row — those move to sections below.
- **"Trusted by" logo wall belongs UNDER the hero, never inside it.**
- **Navigation renders on ONE line at desktop, height ≤ 80px** (default
  64–72px, the scaffolds' `--header-h`). If items don't fit at 1024px, condense
  labels or move to a menu. A two-line desktop nav is broken.
- **Bento grids have rhythm and exact cell count.** N items → N cells; no blank
  filler tiles. Vary composition; and at least 2–3 cells in any multi-cell grid
  need real visual variation (an image, a brand-appropriate gradient, a
  pattern, a tinted background) — an all-same-surface bento with only
  typography inside reads as AI default.
- **SECTION-LAYOUT-REPETITION BAN.** One layout family (3-col cards, full-width
  quote, split text+image…) appears at most ONCE per page. A landing page with
  8 sections uses at least 4 different layout families.
- **ZIGZAG ALTERNATION CAP.** Max 2 consecutive image+text split sections. The
  3rd consecutive zigzag is a pre-flight fail — break it with a full-width
  section, a vertical stack, a bento, or a marquee.
- **EYEBROW RESTRAINT** (the #1 violated rule). An eyebrow is the small
  uppercase wide-tracking label above a section headline (CSS signature:
  `text-transform: uppercase; letter-spacing: 0.18em; font-size ~11px`). Hard
  rule: **max 1 eyebrow per 3 sections**, hero counts as one; if section A has
  one, the next two don't. The check is mechanical: count
  uppercase-tracked micro-labels across templates; count > ⌈sections / 3⌉
  fails. Instead of an eyebrow: drop it — the headline alone is enough.
- **SPLIT-HEADER BAN.** "Left big headline + right small floating explainer
  paragraph" as a section header is banned as default. Stack vertically
  (headline, then body at `--measure`). Reach for a split header only when the
  right column carries a real visual or interactive element.
- **Mobile collapse is explicit per section.** Every multi-column layout
  declares its < 768px fallback in the same stylesheet section. No "the grid
  will probably handle it."

### 4.7 Content density & copy

Landing pages live on the **first impression**, not the full read. Cut
ruthlessly.

- **Default section shape:** short headline (≤ 8 words) + short sub-paragraph
  (≤ 25 words) + one visual asset OR one CTA. More must be justified by the
  section's job. (Docs and book *content* pages are exempt — they're reading
  surfaces; this governs marketing/landing/home compositions.)
- **No data-dump sections.** A 20-row table or 30-item list on a marketing page
  is the wrong layout: top 3–5 highlights + "view full list" link, a marquee /
  scroll-snap row for breadth, or a separate page if the data is the product.
- **Long lists need a different component, not a longer list.** > 5 items:
  2-column grouped split, card grid, tabs/accordion, horizontal scroll-snap
  pills, or a marquee. A 10-row spec sheet with a hairline under every row is
  the worst default — group into 2–3 chunks with sparse dividers, or promote
  3–4 hero specs to display tiles and collapse the rest behind a disclosure.
- **COPY SELF-AUDIT (mandatory before ship).** Re-read every visible string
  (headlines, eyebrows, buttons, captions, alt text, footer). Flag and rewrite
  anything grammatically broken, with unclear referents, or that reads like an
  LLM trying to sound thoughtful (forced metaphors, mock-poetic micro-meta,
  fake-craftsman labels). If unsure whether a string makes sense, replace it
  with a plain functional sentence. AI-cute copy is worse than boring copy.
- **Fake-precise numbers are flagged.** `92%`, `4.1×`, `5.8 mm` either come
  from real data, are explicitly labeled as sample data, or are banned. Don't
  fake engineering precision the brand doesn't claim.
- **One copy register per page.** Don't mix technical-mono metadata, editorial
  prose, and marketing punch unless the brand voice explicitly calls for it.
- **Quotes & testimonials:** max 3 lines of quote body — a landing-page quote
  is a snippet, not the review. Attribution is name + role (+ company), never
  name alone. Real typographic quotes ("") or none — not straight ASCII.

### 4.8 Image & visual asset strategy

Landing pages and portfolios are **visual products**. Text-only pages with
fake-screenshot divs are slop.

**Priority order for visual assets:**

1. **Image-generation tool first.** If ANY image-gen tool is available in the
   environment, use it to create section-specific assets: hero photography,
   product shots, texture backgrounds — at the right aspect ratio per section.
   Save the results into the page bundle or `static/images/` so they're real
   files the build owns.
2. **Placeholder photography second.** No gen tool → 
   `https://picsum.photos/seed/{descriptive-seed}/{w}/{h}` (seed describes the
   section), or stock/brand URLs the brief provides. Treat hotlinks as
   *placeholders*: for the shipped site, download assets into the project so
   the static build is self-contained.
3. **Last resort: tell the user.** Leave clearly-labeled placeholder slots
   (`<!-- TODO: hero product photo, 1600x1200 -->`) and end with: *"This page
   needs real images at: [placements]. Please generate or provide them."* Do
   NOT fill the page with hand-rolled SVG illustrations or div-based fakes.

**Plumbing (Hwaro):** run every real raster asset through
`resize_image(path=…, width=…)` — it returns `.url`, plus `.lqip` (blur-up
placeholder) and `.dominant_color` when LQIP is enabled — and build proper
`srcset`/`sizes` with lazy-loading. Don't ship one giant image. The built-in
processor resizes JPEG/PNG (BMP) sources; `[image_processing] formats =
["webp"]` adds WebP copies (content images get a `<picture>` WebP source, and
`resize_image(…, format="webp")` returns them). For AVIF or other formats run a
build hook — `resize_image` passes unsupported sources through unresized.

**Rules:**

- **Even minimalist sites need real images.** A pure-text landing page is not
  minimalism, it's incomplete. Even a restrained editorial site needs 2–3 real
  images (hero, one product/lifestyle shot, one supporting). Blog/docs *content*
  pages are exempt; their home/landing compositions are not.
- **Div-based fake screenshots are banned.** No fake task lists, fake
  terminals, fake dashboards built from styled `<div>`s. Use a real screenshot,
  a generated image, or skip the preview.
- **Hero needs a real visual.** Text + gradient blob is a placeholder, not a
  hero. (Exception: genuine editorial-manifesto heroes where type IS the
  design.)
- **Real logos for social proof.** A "Trusted by" wall uses real SVG marks —
  vendor them into `static/` (e.g. from Simple Icons) rather than hotlinking a
  CDN; ensure they render in both schemes (single-color via `currentColor` or a
  token). For invented brands, draw a simple monogram mark — a plain text
  wordmark row looks generic. **Logo wall = logos only**: no industry/category
  captions under each logo.

### 4.9 Icons & emoji

- **Use an established icon set, one family per site.** Vendor the SVGs you
  need (Phosphor, Tabler, Radix, Lucide et al. all offer per-icon SVG
  downloads) into `static/icons/` or inline them as partials. Standardize
  `stroke-width` across the set. **Never hand-draw icon paths from scratch.**
- Hand-rolled *decorative* SVGs (custom illustrations, logos) are strongly
  discouraged as a default — acceptable only for a single simple geometric
  mark, or when the user explicitly asks.
- **Emoji are discouraged in markup and visible text** — the emoji-per-card
  feature row is a top AI tell. Use icon glyphs. *Override:* an explicitly
  playful/chat-style brief, sparingly, with intent.

---

## 5. Signature detail

Give the design ONE small recurring mark — an accent rule (the scaffolds use a
short ember rule under the page title), a marker bullet, a consistent hover
behavior — rather than decorating everything. One motif, applied consistently,
reads as identity; five motifs read as noise.

---

## 6. Pattern vocabulary (names to design with)

A vocabulary, not a library — know the names so you can propose and reason
about them. Implementation cost on a static site matters: prefer **pure CSS**,
then **small vanilla JS**, and treat **heavy JS** as a deliberate, justified
exception (there is no bundler unless you add one via build hooks).

- **Hero paradigms:** asymmetric split hero · editorial manifesto hero (type as
  poster) · media-mask hero (type cut out over image/video) · kinetic-type
  hero · scroll-pinned hero (CSS `position: sticky`).
- **Layout & grids:** bento grid · masonry · split-screen scroll ·
  sticky-stack sections (sticky + scroll-driven scale/fade).
- **Cards & containers:** spotlight border card · glassmorphism panel
  (`backdrop-filter` + 1px inner border + inset highlight; solid fallback under
  `prefers-reduced-transparency`) · morphing modal (`<dialog>` + view
  transitions).
- **Scroll effects:** sticky scroll stack · zoom parallax · scroll progress
  bar (`animation-timeline: scroll()`) · reveal-on-enter
  (`animation-timeline: view()` or IntersectionObserver).
- **Typography & text:** kinetic marquee (CSS keyframes; max one per page) ·
  text mask reveal · circular text path (SVG `<textPath>`) · gradient stroke
  text.
- **Micro-interactions:** directional hover fill · ripple click · skeleton
  shimmer · animated SVG line drawing (`stroke-dasharray`).

Heavy-JS patterns (scroll hijack, WebGL scenes, physics cursors) are usually
the wrong trade for a static site; if the brief truly demands one, isolate it
in one small script, lazy-load it, and degrade gracefully without it.

---

## 7. Motion for a static site

No React, no animation framework — and none needed.

**Know what the scaffold already moves** before adding motion: the styled
scaffolds ship an `@starting-style` entry fade of the main content and a sticky
glass masthead (`backdrop-filter: var(--glass-filter)` with a solid fallback),
and `simple` adds cross-document `@view-transition`, all guarded by
`prefers-reduced-motion`. Tune or remove those rather than stacking a second
load-in on top. The toolkit, in order:

1. **CSS transitions** for all interactive states (`var(--transition)`;
   `var(--transition-slow)` / `var(--ease-out)` for bigger moves).
2. **CSS keyframes + `animation-delay` cascades** for load-in staggers
   (`animation-delay: calc(var(--i) * 60ms)` with a per-item `--i`).
3. **CSS scroll-driven animations** (`animation-timeline: view()` /
   `scroll()`) for reveal and progress effects — always behind
   `@supports (animation-timeline: view())` so unsupported browsers get static
   content, not broken content.
4. **IntersectionObserver** (small vanilla script) as the portable reveal
   mechanism:

```html
<script>
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) {
      e.target.classList.add("is-visible");
      io.unobserve(e.target);
    }
  }, { threshold: 0.3 });
  document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));
</script>
```

```css
[data-reveal] { opacity: 0; translate: 0 24px;
  transition: opacity 0.6s cubic-bezier(0.16, 1, 0.3, 1),
              translate 0.6s cubic-bezier(0.16, 1, 0.3, 1); }
[data-reveal].is-visible { opacity: 1; translate: 0 0; }
@media (prefers-reduced-motion: reduce) {
  [data-reveal] { opacity: 1; translate: none; transition: none; }
}
```

**Hard rules:**

- **MOTION MUST BE MOTIVATED.** Before adding any animation ask: what does it
  communicate? Valid: hierarchy, storytelling sequence, feedback, state
  transition. Invalid: "it looked cool." If you can't articulate the reason in
  one sentence, drop it. Not every card needs an infinite loop — informational
  sections stay still.
- **"Motion claimed, motion shown."** If `MOTION_INTENSITY > 4`, the page
  actually moves: hero entry, key-section reveals, CTA hover physics at
  minimum. Can't ship working motion in scope? Drop the dial to 3 and ship a
  clean static page. Never half-build motion that breaks.
- **MARQUEE MAX-ONE-PER-PAGE.** Two marquees on one page is lazy filler.
- **`window.addEventListener("scroll", …)` is banned.** Use scroll-driven CSS,
  IntersectionObserver, or nothing. Same ban for rAF loops recomputing layout
  from `scrollY`.
- **Animate ONLY `transform`/`translate`/`scale` and `opacity`.** Never `top`,
  `left`, `width`, `height`. `will-change` sparingly.
- **Reduced motion is non-negotiable.** Anything above `MOTION_INTENSITY 3`
  honors `prefers-reduced-motion: reduce`: infinite loops, parallax, and
  reveals collapse to static/instant.
- **Grain/noise overlays** live exclusively on a fixed `pointer-events: none`
  element — never on scrolling containers (continuous repaints destroy mobile
  FPS).
- **z-index restraint.** A documented scale for systemic layers (sticky
  header, modal, scrim, grain) — no arbitrary `z-index: 50` sprinkled around.

---

## 8. Dark mode & theme lock

Hwaro's token system (Section 2) makes both schemes nearly free — the
discipline is what remains:

- **PAGE THEME LOCK.** The page has ONE theme: light, dark, or auto
  (`color-scheme: light dark`). Sections never invert mid-scroll — no
  warm-paper section sandwiched between dark sections. Section-level tints
  within the same family are fine (`--bg` next to `--bg-subtle`); a full flip
  is broken. *Exception:* one deliberate full theme-switch device per page,
  only when the brief explicitly calls for it.
- **Hierarchy parity.** If the CTA pops in light, it pops in dark. The brand
  accent stays recognisable in both — don't desaturate the brand into dark
  mode.
- **No pure `#000000` / `#ffffff`** — the ember ink ramp and surfaces model
  this; keep custom pairs off-black/off-white too.
- **Test both modes before finishing.** Screenshot light AND dark (Section 11).
  Never ship a scheme you haven't seen. With the scaffold switcher, force a
  scheme for a screenshot by setting `data-theme` on `<html>` (or the
  `hwaro-theme` localStorage key) instead of changing OS settings.

---

## 9. AI Tells (forbidden patterns)

Avoid these signatures unless the brief explicitly asks for them. These came
out of real production tests of LLM-generated pages — they are what the model
does when it tries to "look designed."

### 9.A Visual & CSS

- NO neon / outer glows by default — inner borders or subtle tinted shadows.
- NO pure black `#000000` — off-black / charcoal (the token ramp).
- NO oversaturated accents; desaturate to sit with the neutrals.
- NO gradient text on large headers as a default move.
- NO custom mouse cursors — outdated, a11y-hostile, perf-hostile.
- NO crosshair / hairline grid lines as pure decoration — hairlines organize
  real content or don't exist.

### 9.B Content & data (the "Jane Doe" effect)

- NO generic names ("John Doe", "Sarah Chan") — creative, locale-appropriate
  names.
- NO generic avatars (SVG egg, user-icon) — believable photo placeholders or
  deliberate styling.
- NO fake-perfect numbers (`99.99%`, `1234567`) — organic, messy data
  (`47.2%`).
- NO startup-slop brand names ("Acme", "Nexus", "SmartFlow") — invent
  contextual names that sound real.
- NO filler verbs: "Elevate", "Seamless", "Unleash", "Next-Gen",
  "Revolutionize" — concrete verbs only.

### 9.C Hero & top-of-page tells

- NO version labels in the hero (`V0.6`, `BETA`, `EARLY ACCESS`) unless the
  brief is literally a launch/preview announcement.
- NO "Brand · No. 01"-style micro-meta sub-eyebrows.
- NO decoration text strip at hero bottom (`DESIGN · BUILD · SHIP`,
  `ESTD. 2018 · LISBON`) — unless the strip carries real navigable links or
  real status.

### 9.D Section numbering & micro-labels

- NO section-number eyebrows (`00 / INDEX`, `001 · Capabilities`,
  `06 · how it works`). Eyebrows name topics in plain language — and are
  rationed anyway (Section 4.6).
- NO `01 / 4` pagination labels on images or bento tiles.
- NO generic step labels ("Step 1 / Step 2 / Step 3", "Phase 01…"). The verb is
  the label: "Install", "Configure", "Ship".
- NO micro-meta sentences under eyebrows ("Each of these is a feature we ship
  today, not a roadmap promise."). Eyebrow + headline + body is enough.

### 9.E Separators, dots, and flourishes

- **The middle-dot (`·`) is rationed:** max 1 per line in metadata strips,
  never the default separator for everything.
- **ZERO decorative status dots by default.** A colored dot before nav items /
  list rows / badges is a tell. Only for real semantic state (live status), at
  most one per section.
- NO `<br>`-broken-and-italicized headlines as a default move — headlines read
  naturally first.
- NO vertical rotated text — agency cliché; only when the brief is explicitly
  experimental AND it serves the composition.

### 9.F Pills, captions, stamps

- NO pills/labels/tags overlaid on images (`PLATE · BRAND`, `Field notes —
  journal`). Let the image speak, or caption below it.
- NO photo-credit captions as decoration (`Field study no. 12 · Ines Caetano`)
  — credit only real photographers on real photos; otherwise a one-line
  functional caption or nothing.
- NO version footers on marketing pages (`v1.4.2`, `Build 0048`,
  `last sync 4s ago`). CLI fixtures, not landing content.
- NO fake live-stock counters ("Reservation 412 of 800") without real data.

### 9.G Marketing-copy tells

- NO "Quietly in use at / Quietly trusted by" — say "Trusted by", "Used at",
  or let the logos speak.
- NO poetic section labels ("From the field", "Currently on the bench", "Loose
  plates") — plain functional labels ("Testimonials", "Latest writing") or
  none.
- NO mock-humble industry references ("We respect the French ones").
- NO locale / city / time / weather strips ("LIS 14:23 · 18°C") for 99% of
  briefs — allowed only for genuinely place-focused or globally-distributed
  briefs. A contact address in the footer is fine; an atmospheric locale strip
  is not.
- NO scroll cues ("Scroll", "↓ scroll to explore", animated mouse icons). The
  user knows what scrolling is.

### 9.H Lists, dividers, scoring

- NO top **and** bottom borders on every row of a long list/spec table — one
  divider direction, used sparsely; better, use a different component
  (Section 4.7).
- NO scoring/progress bars with filled background tracks as comparison visuals
  on marketing pages — a number + small icon, or a tiny trackless bar.

### 9.I EM-DASH BAN (the single most-violated tell)

**The em-dash (`—`) is completely banned in visible page copy.** No "sparingly"
allowance — historically "use sparingly" gets ignored, so the rule is binary:
zero.

- Banned in headlines, eyebrows, labels, pills, buttons, captions, nav items,
  body copy, quotes, attribution, and alt text.
- Restructure instead: two sentences, a comma, parentheses, or a colon.
- The en-dash (`–`) as a separator is banned too. Date ranges (`2018-2026`) and
  number ranges (`€40-80k`) use a plain hyphen.
- Permitted dashes in page copy: the hyphen (`-`) and the math minus (`-5°C`).

This governs the **site's visible copy** (templates and authored demo content
you write). If a single `—` or separator-`–` is visible on the page, the
output fails pre-flight and gets rewritten.

---

## 10. Redesign protocol

This skill handles greenfield builds AND redesigns. Misclassifying the mode is
the biggest source of bad redesign output.

### 10.A Detect the mode (first action)

- **Greenfield** — no existing site, or full overhaul approved.
- **Redesign — preserve** — modernize without breaking the brand. Audit first,
  extract brand tokens, evolve gradually.
- **Redesign — overhaul** — new visual language over existing content. Treat as
  greenfield for visuals; preserve content and IA.

If ambiguous, ask **once**: *"Should this redesign preserve the existing brand,
or are we starting visually from scratch?"*

### 10.B Audit before touching

Document the current state first:

- **Brand tokens** — the existing `:root` values (or, on a non-token site, the
  de-facto palette/type/radii you extract from the CSS).
- **Information architecture** — section tree, nav, key paths.
- **Content blocks** — what exists, what's doing work, what's filler.
- **Patterns to preserve** — signature interactions, recognisable hero, copy
  voice. **Patterns to retire** — AI-slop tells (Section 9), broken layouts,
  generic stock imagery, perf traps.
- **Dial reading of the existing site** — infer its current
  VARIANCE / MOTION / DENSITY; that's your starting point, not the baseline.
- **SEO surface** — page paths, heading-anchor IDs, feed URLs, OG images.
  **SEO migration is the #1 redesign risk on a static site.**

### 10.C Preservation rules

- **Keep URLs stable.** Page paths/slugs, taxonomy paths, and RSS/Atom feed
  URLs don't change unless asked. Heading anchor IDs are generated from heading
  text — rewording headings breaks deep links, so reword deliberately.
- **Extract brand colors before applying Section 4.2.** A brand that is already
  purple stays purple — that's the LILA RULE's override.
- **Preserve copy voice** unless asked for a rewrite. Visual modernization ≠
  content rewrite.
- **Honor existing accessibility wins** — don't regress focus states, alt
  text, keyboard nav, contrast.
- **Never change silently:** URL structure, primary nav labels, the logo /
  wordmark, legal/consent copy, or anything analytics hooks onto.

### 10.D Modernization levers (priority order — stop when the brief is satisfied)

1. **Typography refresh** — biggest visual lift per unit of risk.
2. **Spacing & rhythm** — section padding, vertical rhythm.
3. **Color recalibration** — desaturate, unify neutrals, keep the brand accent.
4. **Motion layer** — dial-appropriate micro-interactions on existing
   components.
5. **Hero & key-section recomposition** — using the Section 6 vocabulary.
6. **Full block replacement** — only when a block is unsalvageable.

Targeted evolution (levers 1–4) captures ~70% of the value at ~40% of the risk
when IA and content are sound. Go full redesign only for structural visual
debt; go greenfield only when the brand itself is changing.

---

## 11. Workflow

1. **Design Read + dials** (Sections 0–1). Infer when you can; short question
   round only when the read genuinely diverges; play back the brief for
   substantial engagements.
2. **Propose direction(s).** Offer 1–3 *distinct* concepts (not three shades of
   one idea), each as a short pitch: the organizing idea, the palette (token
   values), the type pairing, the layout move, the motion stance. Make each
   concrete with a token-value block or ASCII sketch — `AskUserQuestion`
   renders these as side-by-side text previews. Save real visual comparison
   for the browser (step 4). For a confident single read, one declared
   direction is fine — state it and build.
3. **Implement, token-first.** Define/extend the `:root` token layer, *then*
   style components against tokens, *then* assemble layouts in templates. Keep
   markup semantic and accessible from the start. Internal URLs carry
   `{{ base_url }}` (Section 2).
4. **Iterate live — and actually look at it.** Run `hwaro serve` and refine
   with the browser open. If you can't see a browser, build and **screenshot
   with headless Chrome** (`--screenshot`) and review the image — never judge
   a *visual* design from HTML/CSS source alone. Screenshot at a mobile width
   (~390px) AND a desktop width (~1440px), in BOTH color schemes. Hand the
   user the `hwaro serve` URL early; design is a conversation.
5. **Pre-flight, then ship.** Run the full Section 12 check, fix every failing
   box, then present the result and explicitly invite feedback ("warmer /
   denser / quieter?"). Don't declare it done — let the user.

### Two paths

- **Retheme a scaffold (fast path).** `hwaro init my-site --scaffold blog`
  (also `simple` / `docs` / `book`; `bare` ships no CSS at all) gives you a
  complete, accessible, token-driven baseline that already adapts to light *and*
  dark and ships a theme switcher. Often the highest-leverage move is
  **rewriting the token pairs** and a few component rules to the user's brief —
  minutes to a distinctly different site. For a *custom* dark (a warm dark, not
  stock ember-dark), override the dark side of the `light-dark()` pairs —
  the syntax theme follows via `--code-*`. Remember Section 0.D: a retheme
  still needs a Design Read; shipping stock ember unchanged is not a design.
- **Build bespoke.** When the brief needs a layout the scaffolds don't have,
  author templates from scratch (or start from `--scaffold bare`/`simple`) and
  bring your own token system. More work, full control.

---

## 12. Final Pre-Flight Check

Run this before presenting the result. **This is not optional. If any box
fails, the output is not done — fix it first.**

**Read & direction**
- [ ] Design Read declared (one line) with reasoned dial values, not silent
      defaults?
- [ ] Redesign mode detected and audit performed (if applicable)?
- [ ] Result matches the confirmed brief, or the deviation was discussed?
- [ ] One coherent point of view visible throughout — and NOT stock ember
      passed off as a custom design?

**Tokens & color**
- [ ] Everything reads from tokens; no orphan hardcoded colors (scaffold
      hygiene spec stays green when editing scaffold source)?
- [ ] Every custom color pair defines BOTH `light-dark()` sides?
- [ ] One accent, used identically across all pages/sections (Color
      Consistency Lock)?
- [ ] Neutrals are off-black/off-white, never pure `#000`/`#fff`?
- [ ] Premium-consumer brief? Palette is NOT the beige+brass+espresso family
      (i.e., not just re-shipped ember warmth)?
- [ ] Page Theme Lock: one theme, no section inverts mid-page?
- [ ] `--code-*` syntax slots tied to the palette in both schemes?

**Typography**
- [ ] Type scale + line-height + measure deliberate; pairing intentional; CJK
      fallbacks preserved where the audience needs them?
- [ ] Serif discipline: landing/portfolio brief didn't default to serif (and
      never Fraunces / Instrument Serif without explicit brand justification)?
- [ ] Emphasis inside headlines is same-family italic/bold, not mixed-family?
- [ ] Italic display words with descenders have line-height ≥ 1.1 + padding
      reserve?
- [ ] Fonts self-hosted, subset, `font-display: swap`?

**Layout discipline**
- [ ] Hero fits the viewport: headline ≤ 2 lines, subtext ≤ 20 words, CTA
      visible without scroll, `100dvh` not `100vh`?
- [ ] Hero stack ≤ 4 text elements; no tagline/trust-strip/pricing teaser in
      the hero; logo wall UNDER the hero?
- [ ] Hero top padding ≤ ~6rem at desktop?
- [ ] Navigation on one line at desktop, height ≤ 80px?
- [ ] EYEBROW COUNT (mechanical): uppercase-tracked micro-labels ≤
      ⌈sections / 3⌉, hero counts as one?
- [ ] No split-header pattern (left headline + right floating paragraph) as a
      default section header?
- [ ] No 3+ consecutive zigzag image/text splits; ≥ 4 layout families across
      an 8-section page; no layout family repeated?
- [ ] Bento: exact cell count (N items → N cells) and 2–3 cells with real
      visual variation?
- [ ] Shape Consistency Lock: one radius system via `--radius`/`--radius-sm`?
- [ ] Mobile collapse explicit for every multi-column layout; asymmetric
      layouts single-column below 768px?

**Copy & content**
- [ ] ZERO em-dashes (`—`) and zero separator en-dashes (`–`) in visible page
      copy?
- [ ] Copy self-audit done: every visible string re-read, no broken grammar or
      AI-cute phrases?
- [ ] No duplicate CTA intent (one label per intent, page-wide)?
- [ ] CTA labels don't wrap at desktop?
- [ ] Quotes ≤ 3 lines, attribution clean?
- [ ] No fake-precise numbers without real or labeled-sample data?
- [ ] Content density sane: no data-dump tables; long lists use a real
      component, not a hairline-per-row `<ul>`?
- [ ] No leftover lorem ipsum; demo content uses believable names/data
      (Section 9.B)?

**Tells sweep (Section 9)**
- [ ] No version labels/footers, section-number eyebrows, step labels,
      micro-meta sentences?
- [ ] No pills over images, no decorative photo credits, no decoration strips,
      no locale/weather strips, no scroll cues, no decorative dots?
- [ ] Middle-dot rationed; no gradient text defaults, no neon glows, no custom
      cursors?
- [ ] No emoji feature cards; icons from one vendored family, consistent
      stroke?

**Images**
- [ ] Real images present (gen-tool → placeholder-seed → labeled TODO slots) —
      no div-based fake screenshots, no pure-text "minimalism" on a landing?
- [ ] Raster assets through `resize_image` with `srcset`/`sizes`, lazy-loading,
      LQIP where enabled?
- [ ] Logo wall uses real vendored SVG marks, logos only, working in both
      schemes?

**Motion & a11y**
- [ ] Every animation motivated in one sentence; marquee ≤ 1 per page?
- [ ] Motion claimed = motion shown (dial > 4 → the page actually moves; else
      drop the dial)?
- [ ] Only transform/opacity animated; no `window` scroll listeners; grain on
      fixed non-scrolling layers only?
- [ ] `prefers-reduced-motion` collapses everything above dial 3 to static?
- [ ] Contrast ≥ 4.5:1 body / 3:1 large & UI — including every button and
      form field against its own background?
- [ ] Visible `:focus-visible`, skip link, alt text, logical heading order?

**Hwaro plumbing**
- [ ] All internal hrefs/srcs carry `{{ base_url }}` (subpath deploys don't
      404)?
- [ ] Existing URLs, anchors, and feed paths unchanged on a redesign (or the
      change was approved)?
- [ ] Built and **screenshotted at mobile + desktop widths in both schemes**,
      and the screenshots actually reviewed?

---

## See also

- **`hwaro` skill** — operate the CLI (init/new/serve/build/deploy, config & template editing).
- Docs: [Templates](https://hwaro.hahwul.com/templates/) · [Asset Pipeline](https://hwaro.hahwul.com/features/asset-pipeline/) · [Auto Includes](https://hwaro.hahwul.com/features/auto-includes/) · [Image Processing](https://hwaro.hahwul.com/features/image-processing/) · [Build Hooks](https://hwaro.hahwul.com/features/build-hooks/).
