+++
title = "Asset Pipeline"
description = "Built-in CSS/JS bundling, minification, and fingerprinting"
weight = 16
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

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable the asset pipeline |
| `minify` | bool | `true` | Minify CSS/JS output |
| `fingerprint` | bool | `true` | Add content hash to filenames |
| `source_dir` | string | `"static"` | Directory containing source files |
| `output_dir` | string | `"assets"` | Output subdirectory in the build output |

### Bundle definition

Each `[[assets.bundles]]` entry defines a single output file:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Output filename (e.g., `"main.css"`) |
| `files` | array | Source files relative to `source_dir` |

Files are concatenated in the order listed.

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

## How It Works

1. During the Initialize phase, the pipeline reads source files from `source_dir`
2. Files listed in each bundle are concatenated in order
3. If `minify` is enabled, CSS/JS-specific minification is applied
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
