+++
title = "Auto OG Images"
description = "Auto-generate Open Graph preview images from page titles"
weight = 20
toc = true
+++

Hwaro can automatically generate Open Graph (OG) preview images for pages that don't have a custom image set. These images are used by social media platforms when your content is shared.

![Auto-generated OG image for the Auto OG Images page](/og-images/features-og-images.png)
*Example: This is the og image of this page.*

## How It Works

1. During build, Hwaro checks each page for a custom `image` in front matter
2. Pages without an image get an auto-generated image (1200x630)
3. The generated image path is set as `page.image`, so `og:image` meta tags pick it up automatically
4. SVG output requires no external dependencies; PNG output uses built-in rendering via system fonts

## Configuration

```toml
[og.auto_image]
enabled = true
background = "#1a1a2e"
text_color = "#ffffff"
accent_color = "#e94560"
secondary_color = "#3fc7c0"   # optional 2nd color for split/brutalist (auto-derived if omitted)
font_size = 48
logo = "static/logo.png"
logo_position = "bottom-left"
output_dir = "og-images"
show_title = true
style = "default"
pattern_opacity = 0.15
pattern_scale = 1.0
background_image = "static/og-bg.jpg"
overlay_opacity = 0.5
format = "svg"
font_path = "static/fonts/Inter-Bold.ttf"
# lazy_generate = true   # Recommended: true for fast `hwaro serve` on large sites
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `false` | Enable auto OG image generation |
| background | string | `"#1a1a2e"` | Background color (hex) |
| text_color | string | `"#ffffff"` | Title and description text color |
| accent_color | string | `"#e94560"` | Accent color for bars, site name, and geometric color blocks |
| secondary_color | string | — | Second color for two-tone geometric styles (`split`, `brutalist`). When omitted, a complementary tone is auto-derived from `accent_color` |
| font_size | int | `48` | Title font size in pixels |
| logo | string | — | Logo file path (e.g., `static/logo.png`). Embedded as base64 data URI |
| logo_position | string | `"bottom-left"` | Logo placement: `bottom-left`, `bottom-right`, `top-left`, `top-right` |
| output_dir | string | `"og-images"` | Directory for generated images |
| show_title | bool | `true` | Show site name at the bottom of the image |
| style | string | `"default"` | Background style preset.<br>**Modern recommendations**: `editorial` (clean & harmonious), `artistic` (rich backgrounds), `hero`/`surreal`/`monument` (bold & distinctive). |
| pattern_opacity | float | `0.12` | Opacity of the style pattern (0.0–1.0) |
| pattern_scale | float | `1.0` | Scale multiplier for the pattern (min 0.1) |
| background_image | string | — | Background image file path. Embedded as base64 data URI |
| overlay_opacity | float | `0.45` | Opacity of the color overlay on background images (0.0–1.0) |
| format | string | `"svg"` | Output format: `"svg"` or `"png"` |
| font_path | string | — | Path to a custom `.ttf` / `.otf` font file for PNG output. Falls back to system fonts, then the bundled DejaVu Sans Bold |
| text_panel | float | `0.0` | 0.0–0.6. Subtle dark gradient panel behind the title for better harmony with artistic backgrounds. Useful with `editorial`, `framed`, `artistic`, etc. |
| accent_bars | bool | `true` | Draw thin top/bottom accent bars using `accent_color`. Set to `false` for cleaner modern looks (recommended with `editorial` / `artistic` styles). |
| lazy_generate | bool | `false` | When `true`, skip bulk OG image generation during `hwaro serve`. Images are generated on-demand the first time a page is requested. **Recommended for local development on large sites.** Has no effect on `hwaro build`. |

## Style Presets

The `style` option controls the background treatment.

| Style | Description |
|-------|-------------|
| `default` | No pattern (solid background) — classic look |
| `editorial` | **Recommended for modern sites**. Clean style with subtle text panel. Excellent harmony with artistic backgrounds. |
| `framed` | Stronger content card/panel treatment. Good separation from busy backgrounds. |
| `artistic` | Bold style designed for rich/illustrative backgrounds (high-production feel). |
| `hero` | Very large, confident typography with strong focal point. Poster/campaign style. |
| `surreal` | Experimental and dramatic. Heavy background integration with artistic treatment. |
| `monument` | Extreme minimalism. Massive typography + huge whitespace. |
| `split` | **Bold & geometric**. Diagonal two-tone color block on the left with the title on the right. Uses `accent_color` + `secondary_color`. |
| `band` | **Bold & geometric**. Full-width color band with the title knocked out of it (magazine-cover look). Works best with a high-contrast `background`/`accent_color`. |
| `brutalist` | **Bold & geometric**. Thick framed panel with a hard offset shadow block (`secondary_color`) and oversized type. |
| `minimal` | Clean layout without accent bars |
| `dots` | Repeating dot grid |
| `grid` | Repeating line grid |
| `diagonal` | Diagonal stripe pattern |
| `gradient` | Diagonal gradient using the accent color |
| `waves` | Horizontal wave curves |
| `framed` | Stronger content card/panel treatment. Text lives in a more distinct framed area on top of the background. |
| `artistic` | **Bold & modern**. Very strong panel, confident typography, designed for high-production / illustrative / artistic backgrounds. |
| `hero` | Extremely large, bold typography with minimal description. Poster/campaign feel with strong focal point. |
| `surreal` | Experimental and artistic. Heavy background integration, dramatic text treatment. |
| `monument` | Extreme minimalism. Massive typography + huge whitespace. Almost no decorative elements. |
| `editorial` | Modern editorial style — no hard bars, strong text integration via subtle panel, generous breathing room. Great with artistic backgrounds. |
| `split` | Diagonal two-tone color block (accent + secondary) on the left, title/description on the right. Strong editorial/fashion identity. |
| `band` | Solid color band running behind a knocked-out title, description below. Magazine-cover color blocking. |
| `brutalist` | Thick framed panel with a hard offset shadow block and huge type. Neo-brutalist, high-contrast look. |

### Preview

<div class="og-style-grid">
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-default.svg" alt="default style" loading="lazy" />
    <span class="og-style-label"><code>default</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-default.svg" alt="default style" />
        <p><code>default</code> — No pattern (solid background)</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-dots.svg" alt="dots style" loading="lazy" />
    <span class="og-style-label"><code>dots</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-dots.svg" alt="dots style" />
        <p><code>dots</code> — Repeating dot grid</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-grid.svg" alt="grid style" loading="lazy" />
    <span class="og-style-label"><code>grid</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-grid.svg" alt="grid style" />
        <p><code>grid</code> — Repeating line grid</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-diagonal.svg" alt="diagonal style" loading="lazy" />
    <span class="og-style-label"><code>diagonal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-diagonal.svg" alt="diagonal style" />
        <p><code>diagonal</code> — Diagonal stripe pattern</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-gradient.svg" alt="gradient style" loading="lazy" />
    <span class="og-style-label"><code>gradient</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-gradient.svg" alt="gradient style" />
        <p><code>gradient</code> — Diagonal gradient using the accent color</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-waves.svg" alt="waves style" loading="lazy" />
    <span class="og-style-label"><code>waves</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-waves.svg" alt="waves style" />
        <p><code>waves</code> — Horizontal wave curves</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-minimal.svg" alt="minimal style" loading="lazy" />
    <span class="og-style-label"><code>minimal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-minimal.svg" alt="minimal style" />
        <p><code>minimal</code> — Clean layout without accent bars</p>
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
        <p><code>editorial</code> — Clean type with a vertical accent rule</p>
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
        <p><code>framed</code> — Elegant thin inset frame</p>
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
        <p><code>artistic</code> — Vivid two-color gradient backdrop</p>
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
        <p><code>hero</code> — Dramatic spotlight glow with big type</p>
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
        <p><code>surreal</code> — Soft aurora orbs in two colors</p>
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
        <p><code>monument</code> — Massive type with a single rule</p>
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

### Example Configuration

```toml
[og.auto_image]
enabled = true
style = "dots"
pattern_opacity = 0.2
pattern_scale = 1.5
```

## Background Image

You can set a custom background image that gets composited behind the text:

```toml
[og.auto_image]
enabled = true
background_image = "static/og-bg.jpg"
overlay_opacity = 0.6
```

The rendering order is: background color → background image → color overlay → style pattern → accent bars → text/logo.

The `overlay_opacity` controls how much the background color covers the image (0.0 = fully visible image, 1.0 = image completely hidden behind background color).

## PNG Output

By default, images are generated as SVG. Set `format = "png"` to produce PNG files instead:

```toml
[og.auto_image]
enabled = true
format = "png"
```

PNG rendering is built-in using stb_truetype and stb_image_write — no external tools required. System fonts are auto-detected:

- **macOS**: Helvetica, Arial, Geneva
- **Linux**: DejaVu Sans, Liberation Sans, Noto Sans

If no system font is found, Hwaro falls back to SVG output with a warning.

## Generated Image Layout

Each image is 1200x630 with the following structure:

```
┌─────────────────────────────────────┐
│ ████████████ accent bar ████████████│
│                                     │
│   Page Title (auto-wrapped,         │
│   bold, large font)                 │
│                                     │
│   Description text (smaller,        │
│   semi-transparent)                 │
│                                     │
│   [logo] Site Name                  │
│ ████████████ accent bar ████████████│
└─────────────────────────────────────┘
```

When `style = "minimal"`, the top and bottom accent bars are removed. When `show_title = false`, the site name at the bottom is hidden.

## Logo Embedding

When a `logo` file path is configured and the file exists, the logo is read and embedded as a base64 data URI directly in the image. This ensures the logo displays correctly everywhere without external file references.

If the file is not found at build time, the logo falls back to a URL reference (SVG only).

## Incremental Generation

Hwaro tracks a content hash for each page (title, description, URL) and a config hash for OG-related settings. On subsequent builds, only pages whose content or config has changed are regenerated — unchanged images are skipped.

This is managed via a `.og_manifest.json` file stored alongside the generated images. As long as the output directory is preserved between builds (e.g., using `--cache` mode), incremental generation works automatically.

When deploying via the GitHub Actions (`hahwul/hwaro` action), OG image caching is handled automatically — the action restores previously generated images from the `gh-pages` branch before building and enables `--cache` mode.

### What triggers regeneration

| Change | Regenerates |
|--------|-------------|
| Page title, description, or URL | That page only |
| OG config (colors, style, format, etc.) | All pages |
| Image file missing on disk | That page only |

## Performance in Development

Auto-generating OG images (especially PNG) is one of the most expensive operations during a build. On large sites this can add 10–30+ seconds to the initial startup of `hwaro serve`.

The `lazy_generate` option lets you defer OG image generation to the first time a page is actually requested:

```toml
[og.auto_image]
enabled = true
lazy_generate = true   # Recommended for local development on large sites
```

### How it works

- **`hwaro build`** is **completely unaffected** — images are generated exactly as before.
- During `hwaro serve`, the build phase **skips** bulk OG image generation when `lazy_generate = true`.
- The first HTTP request for a page that needs an OG image triggers on-demand generation.
- Once generated, the image is cached on disk and served instantly on subsequent requests and rebuilds.

This is especially powerful when combined with `--fast-start`:

```bash
hwaro serve --fast-start
```

You get near-instant feedback on your priority pages while still having correct OG images the moment you preview them in the browser.

### Comparison with `--skip-og-image`

| Option / Flag         | Serve behavior                     | Build behavior       | Recommended when |
|-----------------------|------------------------------------|----------------------|------------------|
| `--skip-og-image`     | No OG images at all (even on request) | None generated      | You don't use auto OG images |
| `lazy_generate = true`| Generated on first request (lazy) | Normal (eager)      | Fast dev server startup on big sites |
| (default)             | Generated during initial build     | Normal (eager)      | Small sites or when you want OG images immediately in dev |

The default remains `lazy_generate = false` so existing workflows are unchanged.

See also the updated comment in the generated config snippets from `hwaro init` and `hwaro doctor --fix`.

## Behavior

- Pages with a custom `image` in front matter are **skipped** (the custom image takes priority)
- Draft pages are **skipped**
- Long titles are automatically **word-wrapped** across multiple lines
- Logo and background images are loaded once and reused across all pages
- SVG output uses `system-ui` font family; PNG output uses detected system fonts

## Output

Given a page at `/posts/hello-world/`, the generated image will be:

```
public/og-images/posts-hello-world.svg   # or .png if format = "png"
```

And the OG meta tag will automatically include:

```html
<meta property="og:image" content="https://example.com/og-images/posts-hello-world.svg">
```

## Overriding Per Page

To use a custom image for a specific page, set `image` in front matter:

```toml
+++
title = "My Post"
image = "/images/custom-og.png"
+++
```

This page will use the custom image instead of auto-generating one.

## See Also

- [SEO](/features/seo/) — OpenGraph, Twitter Cards, and meta tags
- [Image Processing](/features/image-processing/) — Responsive image resizing
- [Configuration](/start/config/) — Full config reference
