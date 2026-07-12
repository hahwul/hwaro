+++
title = "Auto OG Images"
description = "Auto-generate Open Graph preview images from page titles"
weight = 3
toc = true
+++

Hwaro auto-generates 1200x630 Open Graph preview images for every page that has no custom `image` in front matter. The generated path is set as `page.image`, so `og:image` meta tags pick it up automatically — no template changes needed.

![Auto-generated OG image for the Auto OG Images page](/og-images/features-og-images.png)
*The auto-generated OG image for this page (`style = "terminal"`).*

## Quick Start

```toml
[og.auto_image]
enabled = true
style = "terminal"
accent_color = "#2ee66b"
logo = "static/logo.png"
```

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `false` | Enable auto OG image generation |
| style | string | `"default"` | Composition preset — see [Style Presets](#style-presets) |
| background | string | `"#171310"` | Background color (hex) |
| text_color | string | `"#f4ede4"` | Title and description text color |
| accent_color | string | `"#ec7a66"` | Accent color for rules, brand marks, and color blocks |
| secondary_color | string | — | Second color for two-tone styles (`split`, `brutalist`, `bauhaus`, …). Auto-derived from `accent_color` when omitted |
| font_size | int | `48` | Title font size in pixels. Every style raises this to its own scale automatically unless you set a larger value |
| logo | string | — | Logo file path (e.g., `static/logo.png`), embedded into the image |
| logo_position | string | `"bottom-left"` | `bottom-left`, `bottom-right`, `top-left`, `top-right` |
| show_title | bool | `true` | Show the site name (bottom brand row, or the style's own placement — eyebrow, kicker, window title bar) |
| output_dir | string | `"og-images"` | Directory for generated images |
| format | string | `"png"` | `"png"` or `"svg"`. Social platforms don't render SVG `og:image`, so PNG is the default |
| font_path | string | — | Custom `.ttf`/`.otf` for PNG output. Leads the font chain; glyphs it lacks fall back to the bundled fonts |
| background_image | string | — | Background photo composited behind the text |
| overlay_opacity | float | `0.45` | How much `background` color covers the photo (0.0 = full photo, 1.0 = hidden) |
| text_panel | float | `0.0` | 0.0–0.6. Soft panel behind the text for legibility on busy backgrounds |
| pattern_opacity | float | `0.35` | Peak alpha of the pattern styles (`dots`, `grid`, …). Each pattern fades internally from this peak |
| pattern_scale | float | `1.0` | Scale multiplier for the pattern styles (min 0.1) |
| accent_bars | bool | `false` | Classic thin top/bottom accent bars on the pattern styles |
| lazy_generate | bool | `false` | Skip bulk generation during `hwaro serve`; images render on first request. Recommended for large sites. No effect on `hwaro build` |

Titles render in Space Grotesk, descriptions in Space Grotesk Medium, and the `terminal` style in JetBrains Mono — all bundled into the binary, so PNG output looks the same on every machine. A CJK-capable system font is appended to the chain automatically when your titles need it, and DejaVu Sans Bold backstops everything else.

## Style Presets

The `style` option controls the entire composition. Click any preview below to zoom.

**Signature** — complete, self-contained compositions:

| Style | Description |
|-------|-------------|
| `terminal` | Code-editor window with traffic lights, `$` prompt, and block cursor. Made for dev blogs and docs |
| `bauhaus` | Flat geometric art-poster shapes in accent/secondary/derived colors |
| `halftone` | Print-style halftone dot field fading in from the right edge |

**Modern** — typography-driven with generated backdrops:

| Style | Description |
|-------|-------------|
| `editorial` | Magazine front: hairline rules, an uppercase site-name kicker, and a vertical accent rule. A safe, harmonious default |
| `artistic` | Mesh-gradient color field with film grain. Rich, high-production feel |
| `hero` | Spotlight glow, oversized ghost echo of the first title word, poster typography |
| `surreal` | Aurora orbs and flowing ribbon bands with grain |
| `monument` | Extreme minimalism — massive type, vast whitespace, an accent rule above the title, brand row bottom-right |
| `framed` | Invitation card: a neutral hairline frame with accent corner brackets and centered type |

**Geometric** — bold flat color blocking:

| Style | Description |
|-------|-------------|
| `split` | Diagonal two-tone color block on the left, title on the right |
| `band` | Full-width color band with the title knocked out of it, echoed by a thin rule above — magazine-cover style |
| `brutalist` | Thick framed panel with a hard offset shadow and oversized type |

**Patterns** — compositions with a focal point (each fades internally from `pattern_opacity`):

| Style | Description |
|-------|-------------|
| `default` | Masthead: uppercase site-name eyebrow on top, a low corner glow, and a gentle vignette |
| `minimal` | Nothing but type — and an accent full stop after the title |
| `dots` | Staggered halftone dots fading in from the top-right corner |
| `grid` | Fine blueprint grid with a focal crosshair and registration marks |
| `diagonal` | 45° stripe wedge in the bottom-right corner with an accent rule on the hypotenuse |
| `gradient` | Accent-tinted duotone wash with a corner glow, vignette, and grain |
| `waves` | Layered tide bands anchored to the bottom edge |

### Preview

<div class="og-style-grid">
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-terminal.png" alt="terminal style" loading="lazy" />
    <span class="og-style-label"><code>terminal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-terminal.png" alt="terminal style" />
        <p><code>terminal</code> — Code-editor window with prompt and cursor</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-bauhaus.png" alt="bauhaus style" loading="lazy" />
    <span class="og-style-label"><code>bauhaus</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-bauhaus.png" alt="bauhaus style" />
        <p><code>bauhaus</code> — Flat geometric art-poster shapes</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-halftone.png" alt="halftone style" loading="lazy" />
    <span class="og-style-label"><code>halftone</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-halftone.png" alt="halftone style" />
        <p><code>halftone</code> — Print-style halftone dot fade</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-editorial.png" alt="editorial style" loading="lazy" />
    <span class="og-style-label"><code>editorial</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-editorial.png" alt="editorial style" />
        <p><code>editorial</code> — Magazine front: rules, kicker, and a vertical accent rule</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-artistic.png" alt="artistic style" loading="lazy" />
    <span class="og-style-label"><code>artistic</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-artistic.png" alt="artistic style" />
        <p><code>artistic</code> — Mesh-gradient color field with film grain</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-hero.png" alt="hero style" loading="lazy" />
    <span class="og-style-label"><code>hero</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-hero.png" alt="hero style" />
        <p><code>hero</code> — Spotlight glow with a ghost type echo</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-surreal.png" alt="surreal style" loading="lazy" />
    <span class="og-style-label"><code>surreal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-surreal.png" alt="surreal style" />
        <p><code>surreal</code> — Aurora orbs and flowing ribbons</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-monument.png" alt="monument style" loading="lazy" />
    <span class="og-style-label"><code>monument</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-monument.png" alt="monument style" />
        <p><code>monument</code> — Massive type with an accent rule above the title</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-framed.png" alt="framed style" loading="lazy" />
    <span class="og-style-label"><code>framed</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-framed.png" alt="framed style" />
        <p><code>framed</code> — Hairline frame with accent corner brackets</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-split.png" alt="split style" loading="lazy" />
    <span class="og-style-label"><code>split</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-split.png" alt="split style" />
        <p><code>split</code> — Diagonal two-tone color block</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-band.png" alt="band style" loading="lazy" />
    <span class="og-style-label"><code>band</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-band.png" alt="band style" />
        <p><code>band</code> — Magazine color band behind a knocked-out title</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-brutalist.png" alt="brutalist style" loading="lazy" />
    <span class="og-style-label"><code>brutalist</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-brutalist.png" alt="brutalist style" />
        <p><code>brutalist</code> — Thick framed panel with a hard offset shadow</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-default.png" alt="default style" loading="lazy" />
    <span class="og-style-label"><code>default</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-default.png" alt="default style" />
        <p><code>default</code> — Masthead: eyebrow, corner glow, and vignette</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-minimal.png" alt="minimal style" loading="lazy" />
    <span class="og-style-label"><code>minimal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-minimal.png" alt="minimal style" />
        <p><code>minimal</code> — Nothing but type and an accent full stop</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-dots.png" alt="dots style" loading="lazy" />
    <span class="og-style-label"><code>dots</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-dots.png" alt="dots style" />
        <p><code>dots</code> — Halftone dots fading from the top-right corner</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-grid.png" alt="grid style" loading="lazy" />
    <span class="og-style-label"><code>grid</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-grid.png" alt="grid style" />
        <p><code>grid</code> — Blueprint grid with a focal crosshair</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-diagonal.png" alt="diagonal style" loading="lazy" />
    <span class="og-style-label"><code>diagonal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-diagonal.png" alt="diagonal style" />
        <p><code>diagonal</code> — Stripe wedge with an accent hypotenuse rule</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-gradient.png" alt="gradient style" loading="lazy" />
    <span class="og-style-label"><code>gradient</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-gradient.png" alt="gradient style" />
        <p><code>gradient</code> — Duotone wash with glow, vignette, and grain</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-waves.png" alt="waves style" loading="lazy" />
    <span class="og-style-label"><code>waves</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-waves.png" alt="waves style" />
        <p><code>waves</code> — Layered tide bands along the bottom edge</p>
      </div>
    </dialog>
  </div>
</div>

<style>
.og-style-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 16px;
  margin: 24px 0;
}
.og-style-card {
  cursor: pointer;
  border-radius: 8px;
  overflow: hidden;
  border: 1px solid var(--border, #1e1e24);
  background: var(--bg-card, #111114);
  transition: transform 0.2s, box-shadow 0.2s;
}
.og-style-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
  border-color: var(--border-light, #2e2e36);
}
.og-style-card > img {
  width: 100%;
  display: block;
}
.og-style-label {
  display: block;
  padding: 8px 12px;
  font-size: 14px;
}
.og-style-card dialog {
  padding: 0;
  border: none;
  background: transparent;
  max-width: 90vw;
  max-height: 90vh;
}
.og-style-card dialog::backdrop {
  background: rgba(0, 0, 0, 0.7);
}
.og-style-dialog {
  position: relative;
  background: var(--bg-elevated, #101014);
  border: 1px solid var(--border, #1e1e24);
  border-radius: 8px;
  overflow: hidden;
}
.og-style-dialog > img {
  display: block;
  max-width: 90vw;
  max-height: 80vh;
  object-fit: contain;
}
.og-style-dialog > button {
  position: absolute;
  top: 8px;
  right: 8px;
  background: rgba(0, 0, 0, 0.6);
  color: #fff;
  border: none;
  border-radius: 50%;
  width: 32px;
  height: 32px;
  font-size: 20px;
  line-height: 1;
  cursor: pointer;
  z-index: 1;
}
.og-style-dialog > p {
  text-align: center;
  padding: 12px;
  margin: 0;
}
</style>

## Background Image

Composite a photo behind the text:

```toml
[og.auto_image]
enabled = true
style = "editorial"
background_image = "static/og-bg.jpg"
overlay_opacity = 0.55
```

Rendering order: background color → photo → color overlay → style composition → text/logo. `overlay_opacity` controls how much the background color dims the photo. Styles that generate their own backdrop (`artistic`, `hero`, `surreal`) skip it when a photo is set, so the photo shows through.

### Preview

The examples below differ only in `overlay_opacity` (same photo, `style = "editorial"`, near-black `background`). Click to zoom.

<div class="og-style-grid">
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/bg-image-low.png" alt="background image with low overlay" loading="lazy" />
    <span class="og-style-label"><code>overlay_opacity = 0.3</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/bg-image-low.png" alt="background image with low overlay" />
        <p><code>overlay_opacity = 0.3</code> — Photo stays vivid</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/bg-image-mid.png" alt="background image with balanced overlay" loading="lazy" />
    <span class="og-style-label"><code>overlay_opacity = 0.55</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/bg-image-mid.png" alt="background image with balanced overlay" />
        <p><code>overlay_opacity = 0.55</code> — Balanced photo and text</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/bg-image-high.png" alt="background image with high overlay" loading="lazy" />
    <span class="og-style-label"><code>overlay_opacity = 0.8</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/bg-image-high.png" alt="background image with high overlay" />
        <p><code>overlay_opacity = 0.8</code> — Photo dimmed, text dominant</p>
      </div>
    </dialog>
  </div>
</div>

## Output Format

PNG is the default — rendering is built-in via stb_truetype and stb_image_write, no external tools required. System fonts are auto-detected (Helvetica/Arial on macOS, DejaVu/Liberation/Noto on Linux), with a bundled DejaVu Sans Bold as the last resort.

Titles with CJK characters need a CJK-capable `font_path` (e.g. Noto Sans CJK) — the bundled fonts cover Latin scripts only.

Set `format = "svg"` for dependency-free SVG output instead. Note that social platforms generally don't render SVG `og:image`.

## Incremental Generation

Hwaro stores a `.og_manifest.json` next to the generated images and skips pages whose inputs haven't changed. Keep the output directory between builds (e.g. `--cache` mode) and incremental generation works automatically — the `hahwul/hwaro` GitHub Action handles this for you.

| Change | Regenerates |
|--------|-------------|
| Page title, description, or URL | That page only |
| OG config, or the logo / background image **file contents** | All pages |
| Image file missing on disk | That page only |

## Faster Dev Server

OG generation is one of the most expensive build steps on large sites. Two options:

- `lazy_generate = true` — `hwaro serve` skips bulk generation; each image renders on the first request for its page and is cached after that. `hwaro build` is unaffected. Pairs well with `hwaro serve --fast-start`.
- `hwaro build --skip-og-image` — skips OG images entirely.

## Behavior

- Pages with a custom `image` in front matter keep it; drafts are skipped
- Long titles word-wrap automatically (CJK-aware)
- Logo and background images are loaded once and reused across all pages

## Output

A page at `/posts/hello-world/` produces `public/og-images/posts-hello-world.png` and:

```html
<meta property="og:image" content="https://example.com/og-images/posts-hello-world.png">
```

To use a custom image for a specific page, set `image` in front matter:

```toml
+++
title = "My Post"
image = "/images/custom-og.png"
+++
```

## See Also

- [SEO](/features/seo/) — OpenGraph, Twitter Cards, and meta tags
- [Image Processing](/features/image-processing/) — Responsive image resizing
- [Configuration](/start/config/) — Full config reference
