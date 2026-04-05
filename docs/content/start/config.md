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
| definition_lists | bool | true | Enable definition list syntax (`Term\n: Definition`) |
| mermaid | bool | false | Render ` ```mermaid ` blocks as `<div class="mermaid">` |
| math | bool | false | Enable math syntax (`$...$` and `$$...$$`) |
| math_engine | string | "katex" | Math rendering engine (`"katex"` or `"mathjax"`) |

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
paginate = 10

[[taxonomies]]
name = "categories"
feed = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | — | Taxonomy name (used in front matter) |
| feed | bool | false | Generate RSS feed for each term |
| sitemap | bool | true | Include taxonomy pages in sitemap |
| paginate | int | — | Pages per pagination page |

## Feature Configuration Reference

Each feature has its own documentation with full configuration details. Below is a quick reference of all `config.toml` sections.

| Config Section | Documentation | Description |
|----------------|---------------|-------------|
| `[feeds]` | [SEO](/features/seo/) | RSS/Atom feed generation |
| `[sitemap]` | [SEO](/features/seo/) | Sitemap XML generation |
| `[robots]` | [SEO](/features/seo/) | Robots.txt generation |
| `[og]` | [SEO](/features/seo/) | OpenGraph & Twitter Card meta tags |
| `[og.auto_image]` | [Auto OG Images](/features/og-images/) | Auto-generate OG preview images |
| `[search]` | [Search](/features/search/) | Client-side search index |
| `[highlight]` | [Syntax Highlighting](/features/syntax-highlighting/) | Code syntax highlighting |
| `[pagination]` | [Pagination](/features/pagination/) | Section pagination |
| `[auto_includes]` | [Auto Includes](/features/auto-includes/) | Auto-include CSS/JS files |
| `[assets]` | [Asset Pipeline](/features/asset-pipeline/) | CSS/JS minification & fingerprinting |
| `[image_processing]` | [Image Processing](/features/image-processing/) | Image resizing & LQIP |
| `[image_processing.lqip]` | [Image Processing](/features/image-processing/#lqip-low-quality-image-placeholders) | Base64 blur-up placeholders |
| `[content.files]` | [Content Files](/features/content-files/) | Publish non-Markdown files |
| `[series]` | [Series](/features/series/) | Group posts into ordered series |
| `[related]` | [Related Posts](/features/related-posts/) | Related content recommendations |
| `[llms]` | [LLMs.txt](/features/llms-txt/) | AI/LLM crawler instructions |
| `[pwa]` | [PWA](/features/pwa/) | Progressive Web App support |
| `[amp]` | [AMP](/features/amp/) | Accelerated Mobile Pages |
| `[deployment]` | [Deploy](/deploy/) | Deploy targets configuration |
| `[doctor]` | [Doctor](/start/tools/doctor/) | Suppress known diagnostic issues |
| `languages.*` | [Multilingual](/features/multilingual/) | Multi-language support |

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

# Feature sections — see Feature Configuration Reference above
# [feeds], [sitemap], [robots], [og], [search], [highlight],
# [pagination], [auto_includes], [assets], [image_processing],
# [series], [related], [llms], [pwa], [amp], [deployment], etc.
```

## See Also

- [CLI](/start/cli/) — Command-line options that override config
- [Environment-Specific Config](/features/env-config/) — Per-environment overrides (`config.production.toml`)
