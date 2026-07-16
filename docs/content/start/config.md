+++
title = "Configuration"
description = "Site configuration reference for config.toml"
weight = 4
toc = true
+++

All site configuration lives in `config.toml` at the project root.

## Site Settings

```toml
title = "My Site"
description = "Site description for SEO"
base_url = "https://example.com"
```

| Key | Type | Description |
|-----|------|-------------|
| title | string | Site title |
| description | string | Site description |
| base_url | string | Production URL (no trailing slash) |

## Environment Variables

You can reference environment variables in `config.toml`. Values are substituted before TOML parsing.

```toml
base_url = "${SITE_URL}"
title = "$SITE_TITLE"
description = "${SITE_DESC:-My awesome site}"
```

| Syntax | Description |
|--------|-------------|
| `${VAR}` | Substitute with env var value |
| `$VAR` | Same as above (bare form) |
| `${VAR:-default}` | Use `default` if `VAR` is unset or empty |

Missing variables without defaults are left as-is and produce a build warning. See [Environment Variables](/features/env-variables/) for template usage.

## Build Options

```toml
[build]
output_dir = "public"
drafts = false
parallel = true
cache = false
hooks.pre = ["npm install", "npx tsc"]
hooks.post = ["npm run minify"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| output_dir | string | "public" | Output directory |
| drafts | bool | false | Include draft content |
| parallel | bool | true | Parallel processing |
| cache | bool | false | Enable build caching |
| hooks.pre | array | [] | Commands to run before build |
| hooks.post | array | [] | Commands to run after build |

See [Build Hooks](/features/build-hooks/) for error handling and use cases.

## Markdown

```toml
[markdown]
safe = false
lazy_loading = true
emoji = true
footnotes = true
task_lists = true
definition_lists = true
mermaid = false
math = false
math_engine = "katex"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| safe | bool | false | Strip raw HTML from markdown |
| lazy_loading | bool | false | Automatically add `loading="lazy"` to images |
| emoji | bool | false | Convert emoji shortcodes (e.g. `:smile:`) to emoji characters |
| footnotes | bool | true | Enable footnote syntax (`[^1]`) |
| task_lists | bool | true | Enable task list syntax (`- [ ]` / `- [x]`) |
| task_list_classes | bool | false | Add GFM classes (`task-list-item`, `contains-task-list`) to task-list markup |
| definition_lists | bool | true | Enable definition list syntax (`Term\n: Definition`) |
| mermaid | bool | false | Render ` ```mermaid ` blocks as `<div class="mermaid">` |
| math | bool | false | Enable math syntax (`$...$` and `$$...$$`) |
| math_engine | string | "katex" | Math rendering engine (`"katex"` or `"mathjax"`) |
| smart_punctuation | bool | false | Typographic quotes/dashes/ellipses (`"x"` → “x”, `--` → –, `...` → …) |
| containers | bool | false | `:::note Title` … `:::` custom containers (admonition markup) |
| insert_anchor_links | string | "none" | Site-wide heading anchor links: `"none"`, `"left"`, or `"right"` (page front matter overrides) |
| external_links_target_blank | bool | false | Add `target="_blank" rel="noopener"` to absolute http(s) links |
| external_links_no_follow | bool | false | Add `rel="nofollow"` to absolute http(s) links |
| external_links_no_referrer | bool | false | Add `rel="noreferrer"` to absolute http(s) links |

See [Markdown Extensions](/features/markdown-extensions/) for syntax details and examples.

## Permalinks

Rewrite content directory paths to custom URL paths. Useful for site restructuring without breaking links.

```toml
[permalinks]
"old/posts" = "posts"
"2023/drafts" = "archive/2023"
```

| Source (Directory) | Target (URL Path) | Example Effect |
|-------------------|-------------------|----------------|
| `content/old/posts/a.md` | `posts/` | `/old/posts/a/` -> `/posts/a/` |

## Taxonomies

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate_by = 10

[[taxonomies]]
name = "categories"
feed = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | — | Taxonomy name (used in front matter) |
| feed | bool | false | Generate RSS feed for each term |
| sitemap | bool | true | Include taxonomy pages in sitemap |
| paginate_by | int | — | Items per page on term pages |

## Menus

Named navigation menus, rendered in templates via `site.menus` / `get_menu()`.

```toml
[[menus.main]]
name = "Posts"
url = "/posts/"
weight = 1

[[menus.main]]
name = "About"
url = "/about/"
weight = 2
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | — | **Required.** Entry skipped (with a warning) if missing. |
| url | string | "" | Root-relative or absolute `http(s)://`/`//` URL. |
| weight | int | 0 | Sort order within the menu. |
| identifier | string | `name` | Unique key other entries reference via `parent`. |
| parent | string | none | Nest this entry under another entry's `identifier`. |

Pages/sections can also join a menu from their own front matter (`menus = ["main"]`) without touching this file. A `[languages.<code>]` block with no menus table inherits this global set; declaring `[[languages.<code>.menus.<name>]]` replaces it for that language. See [Menus](/features/menus/) for the full reference (hierarchy, per-language behavior, `active_path` styling).

## Static Files

Everything under `static/` is copied verbatim into the site root, preserving its directory structure — `static/css/app.css` is served at `/css/app.css`. Hidden entries are included too, so `static/.well-known/security.txt` is published at `/.well-known/security.txt`. By default Hwaro filters out common OS, editor, and VCS cruft so it never ships to production.

```toml
[static]
use_default_excludes = true              # filter built-in cruft (default)
exclude = ["*.bak", "drafts/**"]         # extra patterns to skip
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| use_default_excludes | bool | true | Filter the built-in cruft denylist (`.DS_Store`, `Thumbs.db`, `desktop.ini`, `.git`, vim swap files, …) |
| exclude | array | [] | Extra patterns to skip. A glob like `*.bak` matches at any depth, `drafts/**` scopes a subtree, and a literal name is anchored to an exact file or directory (`drafts` drops `drafts/…`) |

The built-in denylist only removes cruft — legitimate dot-paths such as `.well-known/` and `.domains` are **never** filtered and are always published, identically for cold and `--cache`/incremental builds. Set `use_default_excludes = false` to disable the built-in filtering entirely.

## Development Server

Options for `hwaro serve` only — they never affect `hwaro build` output.

```toml
[serve]
fast = true                          # always serve in fast dev mode

[serve.headers]
X-Frame-Options = "SAMEORIGIN"
Cache-Control = "no-store"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fast | bool | false | Serve as if `--fast` was passed (skips OG image generation and image processing); explicit CLI skip flags still apply |
| headers | table | {} | Custom HTTP response headers added to every dev-server response; CLI `--header` values win on duplicate keys |

See the [serve command](/start/cli/#serve) for the matching CLI flags.

## Feature Configuration Reference

Each feature has its own documentation with full configuration details. Below is a quick reference of all `config.toml` sections.

| Config Section | Documentation | Description |
|----------------|---------------|-------------|
| `[feeds]` | [SEO](/features/seo/) | RSS/Atom feed generation |
| `[sitemap]` | [SEO](/features/seo/) | Sitemap XML generation |
| `[robots]` | [SEO](/features/seo/) | Robots.txt generation |
| `[og]` | [SEO](/features/seo/) | OpenGraph & Twitter Card meta tags |
| `[og.auto_image]` | [Auto OG Images](/features/og-images/) | Auto-generate OG preview images (including `lazy_generate` for fast dev server) |
| `[search]` | [Search](/features/search/) | Client-side search index |
| `[highlight]` | [Syntax Highlighting](/features/syntax-highlighting/) | Code syntax highlighting |
| `[pagination]` | [Pagination](/features/pagination/) | Section pagination |
| `[auto_includes]` | [Auto Includes](/features/auto-includes/) | Auto-include CSS/JS files |
| `[assets]` | [Asset Pipeline](/features/asset-pipeline/) | CSS/JS minification & fingerprinting |
| `[image_processing]` | [Image Processing](/features/image-processing/) | Image resizing & LQIP |
| `[image_processing.lqip]` | [Image Processing](/features/image-processing/#lqip-low-quality-image-placeholders) | Base64 blur-up placeholders |
| `[content.files]` | [Content Files](/features/content-files/) | Publish non-Markdown files |
| `[static]` | [Static Files](#static-files) | Filter cruft / exclude paths from the `static/` copy |
| `[serve]` | [Development Server](#development-server) | Dev-server response headers & fast mode |
| `[series]` | [Series](/features/series/) | Group posts into ordered series |
| `[related]` | [Related Posts](/features/related-posts/) | Related content recommendations |
| `[llms]` | [LLMs.txt](/features/llms-txt/) | AI/LLM crawler instructions |
| `[pwa]` | [PWA](/features/pwa/) | Progressive Web App support |
| `[amp]` | [AMP](/features/amp/) | Accelerated Mobile Pages |
| `[deployment]` | [Deploy](/deploy/) | Deploy targets configuration |
| `[doctor]` | [Doctor](/start/tools/doctor/) | Suppress known diagnostic issues |
| `languages.*` | [Multilingual](/features/multilingual/) | Multi-language support |
| `[[menus.*]]` | [Menus](/features/menus/) | Named navigation menus |

## Plugins

```toml
[plugins]
processors = ["markdown"]
```

## Full Example

A complete `config.toml` with all core sections. Copy and adjust to your needs.

```toml
title = "My Blog"
description = "A blog about programming"
base_url = "https://myblog.com"
default_language = "en"

[build]
output_dir = "public"
drafts = false
parallel = true
cache = false
hooks.pre = ["npm ci"]
hooks.post = ["npm run optimize"]

[markdown]
safe = false
lazy_loading = true
emoji = false
footnotes = true
task_lists = true

[permalinks]
"old/posts" = "posts"

[plugins]
processors = ["markdown"]

[[taxonomies]]
name = "tags"
feed = true

[[taxonomies]]
name = "categories"

[[menus.main]]
name = "Posts"
url = "/posts/"

# Feature sections — see Feature Configuration Reference above
# [feeds], [sitemap], [robots], [og], [search], [highlight],
# [pagination], [auto_includes], [assets], [image_processing],
# [series], [related], [llms], [pwa], [amp], [deployment], etc.
```

## See Also

- [CLI](/start/cli/) — Command-line options that override config
- [Environment-Specific Config](/features/env-config/) — Per-environment overrides (`config.production.toml`)
