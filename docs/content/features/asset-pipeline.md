+++
title = "Asset Pipeline"
description = "Built-in CSS/JS bundling, minification, and fingerprinting"
weight = 17
toc = true
+++

Hwaro includes a built-in asset pipeline that bundles, minifies, and fingerprints CSS and JS files for production-ready output.

## Features

- **Bundling** — Combine multiple CSS/JS files into single bundles
- **Minification** — Remove comments and whitespace for smaller files
- **Fingerprinting** — Content-hash filenames for cache busting (e.g., `style.a1b2c3d4.css`)
- **Template helper** — `{{ asset(name="style.css") }}` resolves to the fingerprinted path

## Configuration

Add an `[assets]` section to `config.toml`:

```toml
[assets]
enabled = true
minify = true
fingerprint = true

[[assets.bundles]]
name = "main.css"
files = ["css/reset.css", "css/style.css"]

[[assets.bundles]]
name = "app.js"
files = ["js/util.js", "js/app.js"]
```

Bundle `files` may also name `.scss` sources. While `[sass]` is enabled they compile through the [built-in Sass compiler](/features/sass/) before concatenation, then minify and fingerprint like any other CSS. Name such bundles with a `.css` extension so the output serves with the right type.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable the asset pipeline |
| `minify` | bool | `true` | Minify CSS/JS output |
| `fingerprint` | bool | `true` | Add content hash to filenames |
| `source_dir` | string | `"static"` | Directory containing source files (watched by `hwaro serve` wherever it points, as long as it stays inside the project) |
| `output_dir` | string | `"assets"` | Output subdirectory in the build output |
| `sri` | bool | `false` | Add `integrity` attributes to the local CSS/JS tags Hwaro emits (see [Subresource Integrity](#subresource-integrity)). Works with `enabled = false` |

### Bundle definition

Each `[[assets.bundles]]` entry defines a single output file:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Output filename (e.g., `"main.css"`) |
| `files` | array | Source files relative to `source_dir` |

Files are concatenated in the order listed. Keep CSS `@import` rules in the first file: browsers ignore an `@import` that follows other rules, so the build warns about one in a later file.

A CSS bundle is published under `output_dir`, not beside its source files. When `source_dir` is `static`, a relative `url(...)` that points at a file next to the source stylesheet is rewritten to reach the same file from the bundle. For example, `url(img/x.png)` in `static/css/a.css` becomes `url(../css/img/x.png)` in `assets/main.css`. Absolute, `data:` and protocol URLs, and relative URLs with no matching file beside the source, are left as written, and so is `url(...)` text inside a CSS string or comment.

## Template Usage

Use the `asset()` function in templates to reference bundled assets:

```html
<link rel="stylesheet" href="{{ asset(name='main.css') }}">
<script src="{{ asset(name='app.js') }}"></script>
```

When fingerprinting is enabled, this resolves to the hashed path:

```html
<link rel="stylesheet" href="https://example.com/assets/main.a1b2c3d4.css">
```

When the asset is not found in the pipeline manifest (e.g., not configured as a bundle), the function falls back to returning the path as-is under `base_url`.

`asset_url` is available as an alias for `asset`.

## Subresource Integrity

[Subresource Integrity](https://developer.mozilla.org/en-US/docs/Web/Security/Subresource_Integrity) lets the browser refuse a stylesheet or script whose bytes differ from what the page expects. `asset_integrity()` returns the `sha384-…` value of the file `asset()` points to:

```html
<link rel="stylesheet" href="{{ asset(name='main.css') }}" integrity="{{ asset_integrity(name='main.css') }}" crossorigin="anonymous">
```

The hash covers the bytes Hwaro writes to the output (after minify and fingerprint), so it always matches the published file. It works for:

- pipeline bundles
- files copied from `static/`, such as `asset_integrity(name='css/site.css')` for `static/css/site.css`
- Sass outputs
- page-bundle assets and `[content.files]` files, such as `asset_integrity(name='posts/demo/app.js')`. These are copied after rendering, so their source is hashed. The copy is byte-for-byte, except for `.json`, `.xml` and `.html` files under `--minify`: those are rewritten after rendering, so `asset_integrity()` raises for them.

A name that this build does not publish fails the build with a template error. This holds on `--cache` builds too, even while the output directory still holds a copy from an earlier build (a deleted static file, an asset of a page that became a draft).

Set `sri = true` to add the attribute to the tags Hwaro generates itself:

```toml
[assets]
sri = true
```

- `{{ auto_includes }}`, `{{ auto_includes_css }}` and `{{ auto_includes_js }}` ([Auto Includes](/features/auto-includes/))
- `{{ highlight_css }}`, `{{ highlight_js }}` and `{{ highlight_tags }}` when `[highlight] use_cdn = false`

Each tag gets `integrity` together with `crossorigin="anonymous"`. The URLs start with your absolute `base_url`, so a page viewed from another host (`www` vs the apex domain, a deploy preview that keeps the production `base_url`) loads them cross-origin. The browser can only check the integrity of a CORS response; without `crossorigin` it would block the file. Static hosts and CDNs answer such requests (`Access-Control-Allow-Origin`); on your own server, allow it for CSS and JS. Add `crossorigin="anonymous"` to tags you write with `asset_integrity()` for the same reason.

CDN tags get no `integrity`, because Hwaro does not know their bytes. The `?v=` [cache-busting](/features/cache-busting/) query does not affect the hash.

`hwaro serve` leaves `integrity` off the tags it generates. Its pages carry the dev server's own address, which you may open under another name (`localhost` vs `127.0.0.1`, a LAN address). `asset_integrity()` still returns the value under serve.

A changed CSS or JS file updates the value on every page that prints it, both on `hwaro build --cache` and under `hwaro serve`. A stale value would make the browser block the asset.

Tools that rewrite emitted CSS or JS after the build break the check: a `[build] hooks.post` minifier over `public/` changes the bytes after the hashes were printed. Run such tools in `hooks.pre` (writing into `static/`) or use `[assets] minify`. When a post hook does change a file whose integrity a page carries, the build prints a warning naming the file.

## Used-selector manifest (Tailwind)

Utility-CSS tools such as Tailwind CSS v4 generate only the classes your HTML uses. With `[build] write_stats = true`, every build writes `hwaro_stats.json` at the project root (like Hugo's `hugo_stats.json`) listing the tags, classes and ids of every rendered page (pages, sections, taxonomy pages, pagination pages and the 404 page):

```json
{
  "htmlElements": {
    "tags": ["a", "body", "div"],
    "classes": ["flex", "mt-4", "text-lg"],
    "ids": ["main"]
  }
}
```

Values are sorted and de-duplicated. The file is rewritten only when its content changes, and `hwaro serve` never treats it as a source change, so it cannot cause a rebuild loop.

Builds that render every page write the exact set. A partial build (`--cache` hits, `serve --fast-start`, or serve's incremental rebuilds) adds what it rendered to the previous file instead. A class that only an edited or deleted page used then stays listed until the next build that renders every page. Extra entries only mean slightly more generated CSS; no class a page uses is ever missing. If the file is missing or unreadable when a `--cache` build starts, that build renders every page.

Markup inside `<script>` and `<style>` is not scanned, so classes in client-side templates (`<script type="text/template">`) or added by JavaScript are not listed. Add them to your Tailwind sources yourself.

### Tailwind v4 recipe

Point Tailwind at the manifest and run its CLI as a pre-build hook:

```css
/* assets/tailwind.css */
@import "tailwindcss";
@source "../hwaro_stats.json";
```

```toml
[build]
write_stats = true
hooks.pre = ["npx @tailwindcss/cli -i assets/tailwind.css -o static/css/tailwind.css --minify"]
```

```html
<link rel="stylesheet" href="{{ asset(name='css/tailwind.css') }}">
```

The pre-build hook reads the manifest from the previous build, so on a fresh checkout run `hwaro build` twice, or commit `hwaro_stats.json` along with the source.

Under `hwaro serve`, `hooks.pre` runs only on full rebuilds, while content edits update `hwaro_stats.json` incrementally. To pick up new classes as you write, run Tailwind in watch mode next to the server instead of as a hook:

```bash
npx @tailwindcss/cli -i assets/tailwind.css -o static/css/tailwind.css --watch
```

Tailwind rewrites `static/css/tailwind.css`, the server copies it and reloads the page, and the stats file does not change, so the loop settles.

## How It Works

1. During the Initialize phase, the pipeline reads source files from `source_dir`
2. Files listed in each bundle are concatenated in order
3. If `minify` is enabled, CSS/JS-specific minification is applied (`.css`, `.js` and `.mjs` bundles; a UTF-8 BOM at the start of an entry is dropped)
4. If `fingerprint` is enabled, an 8-character SHA-256 hash is inserted before the extension
5. The output is written to `{output_dir}/{output_name}` in the build directory
6. A manifest mapping original names to output paths is stored for template resolution

### Minification

The built-in minifiers are conservative and safe:

**CSS:**
- Removes comments (`/* ... */`)
- Collapses whitespace
- Removes whitespace around `{`, `}`, `:`, `;`, `,`
- Strips trailing semicolons before `}`

**JS:**
- Removes single-line comments (`// ...`) outside strings
- Removes multi-line comments (`/* ... */`)
- Preserves string literals (single, double, and template)
- Removes blank lines

For more aggressive minification, use [build hooks](/features/build-hooks/) with external tools like `esbuild` or `terser`.

## Examples

### Basic CSS bundle

```toml
[assets]
enabled = true

[[assets.bundles]]
name = "style.css"
files = ["css/normalize.css", "css/base.css", "css/layout.css"]
```

```html
<link rel="stylesheet" href="{{ asset(name='style.css') }}">
```

### Multiple bundles

```toml
[assets]
enabled = true

[[assets.bundles]]
name = "vendor.css"
files = ["css/vendor/normalize.css", "css/vendor/highlight.css"]

[[assets.bundles]]
name = "site.css"
files = ["css/base.css", "css/components.css"]

[[assets.bundles]]
name = "app.js"
files = ["js/search.js", "js/nav.js"]
```

### Development without fingerprinting

```toml
[assets]
enabled = true
minify = false
fingerprint = false

[[assets.bundles]]
name = "style.css"
files = ["css/style.css"]
```

## See Also

- [Cache Busting](/features/cache-busting/) — Query-string based cache invalidation for non-pipeline assets
- [Auto Includes](/features/auto-includes/) — Automatically load CSS/JS from static directories
- [Build Hooks](/features/build-hooks/) — Run external tools before/after builds
- [Template Functions](/templates/functions/#asset-integrity) — `asset()` and `asset_integrity()`
