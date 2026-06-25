---
name: hwaro-design
description: >-
  Use when designing or restyling a Hwaro site — choosing a visual direction,
  customizing templates and CSS, building or retheming a theme, picking
  typography and color, or improving an existing layout. ALWAYS interview the
  user about their taste and intent first, then produce distinctive,
  production-grade design within Hwaro's Crinja template + CSS-variable token
  system. Pair with the `hwaro` skill, which covers operating the CLI itself.
---

# Hwaro Design

Your job is to design Hwaro sites that look **intentional, distinctive, and
genuinely good** — and that reflect *this user's* taste, not a generic default.
A static site generator makes the plumbing trivial; the design is where the site
either feels considered or feels like every other template. Aim for the former.

This skill assumes the project is a Hwaro site (config.toml + `templates/` +
`static/`). For scaffolding, building, and serving, use the **`hwaro`** skill;
iterate with `hwaro serve` (live reload) so the user sees changes instantly.

---

## Rule #1 — Interview before you design

**Do not write a single line of CSS until you understand the user's taste.**
The most common failure in AI design is producing competent, generic output
nobody asked for. Avoid it by gathering a *design brief* first.

Ask focused questions and let the answers steer everything. Use the
`AskUserQuestion` tool when it is available (offer 2–4 concrete options per
question with short descriptions; people choose better than they free-associate),
otherwise ask in prose. Prefer showing **examples and contrasts** over abstract
adjectives — "Linear/Vercel-clean vs. editorial-magazine vs. warm-handcrafted"
tells you more than "modern."

Cover, roughly in this order — but stop asking once you have enough to commit:

1. **Purpose & audience.** What is the site (blog, docs, portfolio, landing,
   shop)? Who reads it, on what devices? What should they feel / do?
2. **Personality.** Three adjectives for the vibe (e.g. *calm, editorial,
   precise* vs. *bold, playful, loud*). Ask for 1–3 **reference sites** they
   admire and *what specifically* they like about each.
3. **Color.** Light, dark, or both? A brand color or starting hue? A mood
   (warm/earthy, cool/technical, high-contrast/mono, pastel, neon)? Anything to
   avoid.
4. **Typography.** Serif, sans, or mixed? Classic/literary, geometric/modern,
   technical/monospace, expressive/display? Do they want a real type pairing or
   system fonts for speed?
5. **Density & layout.** Airy and minimal, or rich and dense? Wide or narrow
   measure? Centered single-column, sidebar, or asymmetric?
6. **Motion & detail.** Static and quiet, subtle micro-interactions, or
   expressive animation? (Always honor `prefers-reduced-motion` regardless.)
7. **Constraints.** Performance budget, accessibility/contrast requirements,
   existing brand assets (logo, fonts, palette), must-keep elements, deadline.

Then **play it back**: write the brief in 4–6 lines ("Warm editorial blog:
cream paper background, single rust accent, Charter-style serif headings over a
clean sans body, generous whitespace, motion limited to gentle link/hover
transitions") and confirm before building. The brief is the contract you design
against and the thing you check the result against.

If the user says "just make it look good / surprise me," still commit to **one
clear point of view** and state it ("I'm going bold-editorial with a near-black
canvas and a single electric accent — say the word if you'd rather go lighter").
A confident direction the user can react to beats a safe average.

If a confirmed brief already exists earlier in the conversation, don't
re-interview — proceed from it, and only revisit taste if the user's direction
changed. Interview when intent is genuinely unknown, not as a ritual.

---

## The quality bar

Production-grade design is a stack of deliberate decisions. Hit every layer.

- **A point of view.** Pick one organizing idea (Swiss/grid precision, warm
  editorial, brutalist mono, soft neumorphic, retro terminal, glassy modern…)
  and let it govern every choice. Coherence reads as quality.
- **Typography does the heavy lifting.** Choose a deliberate pairing (or one
  great family with real weight range). Set a **modular type scale** (e.g.
  1.2–1.333 ratio), not ad-hoc px. Tune line-height (~1.5–1.7 body, tighter for
  display), measure (~60–75ch for reading), letter-spacing on large/all-caps
  text, and `text-wrap: balance` on headings / `pretty` on paragraphs.
- **Color with intent.** Build a small, real palette: one dominant surface
  family, considered neutrals (not pure `#000`/`#fff`), and **one** confident
  accent used sparingly for emphasis and interaction. Check contrast (≥ 4.5:1
  body text, ≥ 3:1 large text & UI). Use `color-mix()` for tints/states instead
  of inventing new hex values.
- **A spatial system.** Define a spacing scale (e.g. 4/8px-based steps) and use
  it everywhere. Consistent rhythm, alignment, and generous negative space are
  what make a layout feel composed.
- **Clear hierarchy & a focal point.** Every screen should have an obvious
  entry point and an unambiguous reading order. Size, weight, color, and space —
  not boxes everywhere — establish it.
- **Texture & detail, used with restraint.** Hairline borders, a *single*
  considered shadow elevation, a subtle gradient or grain, a small recurring
  motif (the scaffolds use one short accent rule under the page title). Detail
  signals care; clutter signals the opposite.
- **Motion with purpose.** Short, eased transitions on interactive elements;
  reveal/scroll effects only if they serve the content. Always wrap in
  `@media (prefers-reduced-motion: reduce)`.
- **Responsive by construction.** Design the small screen and the large screen,
  not just a desktop that shrinks. Use fluid type/space (`clamp()`), sensible
  breakpoints, and real touch targets.
- **Accessibility is part of "good," not a checkbox.** Semantic HTML, visible
  `:focus-visible`, a skip link, alt text, sufficient contrast, and a logical
  heading order.

### Refuse the generic-AI look

Actively avoid the tells: everything centered; default system-font-only with no
type personality; the obligatory purple/indigo gradient; three identical
equal-width cards with an emoji on each; pill buttons floating in a sea of
gray-50; meaningless hero blob/gradient mesh; lorem ipsum left in; inconsistent
spacing. If a draft drifts toward this, stop and re-anchor on the brief.

---

## How design lives in a Hwaro site

Know the actual surfaces you can touch — this is what makes the design *real* and
not just advice.

### Templates (Crinja / Jinja2-compatible) — the structure

Under `templates/`. Hwaro supports two composition styles and the built-in
scaffolds use **both**, so open the project's `templates/` and see which before
editing: `{% extends "base.html" %}` inheritance filling `{% block content %}`
(the `docs` scaffold works this way), and `{% include "header.html" %}` /
`{% include "footer.html" %}` partial composition (`blog`, `book`, `simple`).
Other files you'll meet: `page.html` / `section.html` (content layouts),
`index.html` (home), `taxonomy*.html`, and partials like `nav.html` /
`sidebar.html`. Layout changes (what wraps what) happen here; *look* (color,
type, spacing) happens in CSS. Keep markup semantic and class-driven so the CSS
can do the work.

### CSS delivery — three options, pick deliberately

1. **Inlined `<style>`** — the `simple` scaffold ships its CSS in a `<style>`
   block inside `header.html`: zero extra requests, great for small sites; edit
   that block directly. (`blog` / `book` / `docs` instead ship an external
   `static/css/style.css` — option 2; `bare` ships *no* CSS at all, so you bring
   your own.)
2. **Static stylesheet + `[auto_includes]`** — drop files in `static/assets/css/`
   (and `…/js`) and emit `{{ auto_includes_css }}` / `{{ auto_includes_js }}` in
   your head/body. (These output raw HTML; Hwaro disables template autoescape, so
   the scaffolds write them without `| safe` — the docs add `| safe` as a
   harmless, portable convention you can keep.) Good when CSS grows past "one block."
3. **`[assets]` pipeline** — declare bundles in `config.toml`, reference with
   `{{ asset(name='main.css') }}`; you get concatenation, minification, and
   content-hash fingerprinting (cache busting) for free.

> **There is no built-in Sass/SCSS or Tailwind step.** Write modern plain CSS
> (custom properties, nesting where supported, `color-mix`, `clamp`), *or* run
> Sass/Tailwind/PostCSS yourself via **build hooks** and point Hwaro at the
> compiled output. Don't assume a preprocessor exists.

### Design tokens are your single source of truth

Every Hwaro scaffold themes itself through **CSS custom properties** in `:root`.
This is the right pattern: define the system once, theme by editing tokens, and
get dark mode + restyles almost for free. The scaffolds' "Hwaro Ember" token
vocabulary is (hex values exact; font stacks abbreviated — the real ones are
longer and include CJK fallbacks like `"Noto Serif KR"`, so don't strip those if
your audience needs CJK):

```css
:root {
  --primary: #b35454;          /* the single accent */
  --primary-strong: #8f4040;   /* hover/active accent */
  --text: #2a241f;             /* body text (not pure black) */
  --text-muted: #6f6358;       /* secondary text */
  --border: #e4dacd;           /* hairlines */
  --bg: #faf7f2;               /* page canvas (not pure white) */
  --bg-subtle: #f1eae0;        /* code/wells/cards */
  --font-serif: "Charter", Georgia, "Noto Serif KR", serif;   /* headings (+CJK) */
  --font-sans:  -apple-system, "Segoe UI", Roboto, sans-serif;  /* body */
  --font-mono:  ui-monospace, "SF Mono", Menlo, monospace;      /* code */
}
```

**Extend it into a full system** — add the layers a considered design needs, then
build every component against the tokens (never hardcode a raw value in a rule):

```css
:root {
  /* …colors & fonts as above… */

  /* Type scale (1.25 ratio, fluid) */
  --step-0: clamp(1rem, 0.95rem + 0.25vw, 1.125rem);
  --step-1: clamp(1.25rem, 1.1rem + 0.6vw, 1.5rem);
  --step-2: clamp(1.6rem, 1.3rem + 1.2vw, 2.25rem);
  --step-3: clamp(2.1rem, 1.6rem + 2vw, 3.25rem);

  /* Spacing scale (8px base) */
  --space-1: 0.25rem; --space-2: 0.5rem; --space-3: 1rem;
  --space-4: 1.5rem;  --space-5: 2.5rem; --space-6: 4rem;

  /* Shape, depth, motion, measure */
  --radius: 8px;
  --shadow: 0 1px 2px rgba(0,0,0,.04), 0 8px 24px rgba(0,0,0,.06);
  --transition: 0.15s ease;
  --measure: 68ch;            /* max reading width */
}

/* Dark mode by token override — components don't change, only the values do. */
@media (prefers-color-scheme: dark) {
  :root {
    --text: #ece6df; --text-muted: #a89c8e;
    --bg: #14110e; --bg-subtle: #1f1a16; --border: #342d27;
    --primary: #d98a7a; --primary-strong: #e6a293;
  }
}
/* Or make it user-toggleable with a `[data-theme="dark"]` block + a small JS toggle. */
```

### Imagery, fonts, and the small marks

- **Responsive images:** `resize_image(path=…, width=…)` returns `.url`, plus
  `.lqip` (blur-up placeholder) and `.dominant_color` when LQIP is enabled —
  build proper `srcset`/`sizes` and lazy-load. Don't ship one giant image. The
  built-in processor resizes JPEG/PNG (BMP) only; for WebP/AVIF (or aggressive
  optimization) run a build hook — `resize_image` passes unsupported formats
  through unresized.
- **Fonts:** self-host with `@font-face` (the scaffolds embed Charter via OFL
  Charis SIL so headings render the same off-Apple). Subset, `font-display: swap`,
  and limit families/weights — fonts are usually the biggest perf cost of a
  "designed" site.
- **Signature detail:** give the design one small recurring mark (an accent rule,
  a marker bullet, a consistent hover) rather than decorating everything.

---

## Workflow

1. **Interview** → produce and confirm the design brief (Rule #1).
2. **Propose direction(s).** Offer 1–3 *distinct* concepts (not three shades of
   the same idea), each as a short pitch: the organizing idea, the palette
   (token values), the type pairing, the layout move, and the motion stance.
   Make each concrete with a token-value block, an ASCII layout sketch, or a
   short code snippet — `AskUserQuestion` can render these as side-by-side *text*
   previews (not raster mockups). Save real visual comparison for the browser
   (step 4). Get a pick + any tweaks.
3. **Implement, token-first.** Define/extend the `:root` token layer, *then*
   style components against the tokens, *then* assemble layouts in the
   templates. Keep markup semantic and accessible from the start.
4. **Iterate live.** Run `hwaro serve` and refine with the browser open. Show
   the user real results early and often; design is a conversation.
5. **Review & ship.** Walk the pre-ship checklist below, fix gaps, then present
   the result and explicitly invite feedback ("want it warmer / denser /
   quieter?"). Revise. Don't declare it done — let the user.

### Two paths

- **Retheme a scaffold (fast path).** `hwaro init my-site --scaffold blog`
  (also `docs` / `book`, each with a `-dark` variant; `simple` / `bare` are
  light-only) gives you a complete, accessible,
  token-driven baseline. Often the highest-leverage move is just **rewriting the
  token block** and a few component rules to the user's brief — minutes to a
  distinctly different site.
- **Build bespoke.** When the brief needs a layout the scaffolds don't have,
  author templates from scratch (or start from `--scaffold bare`/`simple`) and
  bring your own token system. More work, full control.

---

## Checklists

**Interview (before designing):** purpose & audience ✔ · personality + 1–3
references ✔ · color mood / light-dark ✔ · type feel ✔ · density & layout ✔ ·
motion appetite ✔ · constraints (brand, perf, a11y, deadline) ✔ · brief played
back and confirmed ✔

**Pre-ship (before declaring done):**
- [ ] One coherent point of view, visible throughout.
- [ ] Type scale + line-height + measure deliberate; headings/body pairing intentional.
- [ ] Small real palette; one accent used sparingly; neutrals aren't pure black/white.
- [ ] Consistent spacing scale; generous, rhythmic whitespace; aligned grid.
- [ ] Clear hierarchy and focal point on every key page.
- [ ] Responsive at small **and** large; fluid type/space; real touch targets.
- [ ] Contrast ≥ 4.5:1 (body) / 3:1 (large & UI); visible `:focus-visible`; skip link; alt text; logical headings.
- [ ] Motion eased and purposeful; `prefers-reduced-motion` respected.
- [ ] Images responsive (`resize_image` + `srcset`, lazy, LQIP); fonts subset with `font-display: swap`.
- [ ] No generic-AI tells (centered-everything, default-font, purple gradient, identical emoji cards, leftover lorem).
- [ ] Everything reads from tokens; no orphan hardcoded values.
- [ ] Matches the confirmed brief — or the deviation was discussed.

---

## See also

- **`hwaro` skill** — operate the CLI (init/new/serve/build/deploy, config & template editing).
- Docs: [Templates](https://hwaro.hahwul.com/templates/) · [Asset Pipeline](https://hwaro.hahwul.com/features/asset-pipeline/) · [Auto Includes](https://hwaro.hahwul.com/features/auto-includes/) · [Image Processing](https://hwaro.hahwul.com/features/image-processing/) · [Build Hooks](https://hwaro.hahwul.com/features/build-hooks/).
