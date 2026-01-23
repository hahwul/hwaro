+++
title = "Configuration Reference"
description = "Complete reference for all Hwaro configuration options"
+++


This is the complete reference for all options available in `config.toml`. For a guided introduction, see [Configuration](/getting-started/configuration/).

## Site Settings

Basic site metadata used throughout your site and in meta tags.

```toml
title = "My Site"
description = "A brief description of your site"
base_url = "https://example.com"
```

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `title` | string | Yes | Site title, used in templates and meta tags |
| `description` | string | No | Site description for SEO and social sharing |
| `base_url` | string | Yes | Production URL without trailing slash |

## Plugins

Configure content processors and extensions.

```toml
[plugins]
processors = ["markdown"]
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `processors` | array | `["markdown"]` | List of content processors to enable |

### Available Processors

| Processor | Description |
|-----------|-------------|
| `markdown` | Process Markdown files with TOML front matter |

## Syntax Highlighting

Configure code block syntax highlighting using Highlight.js.

```toml
[highlight]
enabled = true
theme = "github-dark"
use_cdn = true
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable syntax highlighting |
| `theme` | string | `"github"` | Highlight.js theme name |
| `use_cdn` | bool | `true` | Load Highlight.js from CDN |

### Available Themes

Popular theme options:

| Theme | Description |
|-------|-------------|
| `github` | GitHub light theme |
| `github-dark` | GitHub dark theme |
| `monokai` | Monokai dark theme |
| `atom-one-dark` | Atom One Dark theme |
| `atom-one-light` | Atom One Light theme |
| `vs2015` | Visual Studio 2015 dark theme |
| `nord` | Nord color palette theme |
| `dracula` | Dracula dark theme |
| `tomorrow-night` | Tomorrow Night theme |

See [Highlight.js demo](https://highlightjs.org/static/demo/) for all themes.

## Markdown

Configure markdown parsing behavior.

```toml
[markdown]
safe = false
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `safe` | bool | `false` | Strip raw HTML from markdown content |

When `safe` is `true`, any raw HTML in markdown files is replaced with `<!-- raw HTML omitted -->` comments. This is useful for user-generated content or when you want to ensure only markdown formatting is used.

## Search

Generate a client-side search index compatible with Fuse.js.

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content", "tags", "description"]
filename = "search.json"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable search index generation |
| `format` | string | `"fuse_json"` | Index format |
| `fields` | array | `["title"]` | Fields to include in the index |
| `filename` | string | `"search.json"` | Output filename |

### Available Fields

| Field | Description |
|-------|-------------|
| `title` | Page title from front matter |
| `content` | Page content (HTML stripped) |
| `description` | Page description from front matter |
| `tags` | Page tags from front matter |
| `url` | Page URL path |
| `section` | Section the page belongs to |

## Taxonomies

Define content classification systems like tags and categories.

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate_by = 10
sitemap = true

[[taxonomies]]
name = "categories"
feed = false

[[taxonomies]]
name = "authors"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | required | Taxonomy name (used in URLs and front matter) |
| `feed` | bool | `false` | Generate RSS feed for each term |
| `paginate_by` | int | `0` | Items per page (0 = no pagination) |
| `sitemap` | bool | `true` | Include taxonomy pages in sitemap |

### URL Structure

For a taxonomy named `tags`:

- `/tags/` — Taxonomy index (all terms)
- `/tags/crystal/` — Term page (content with tag "crystal")
- `/tags/crystal/rss.xml` — Term feed (if `feed = true`)

## Sitemap

Generate a `sitemap.xml` file for search engine crawlers.

```toml
[sitemap]
enabled = true
filename = "sitemap.xml"
changefreq = "weekly"
priority = 0.5
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable sitemap generation |
| `filename` | string | `"sitemap.xml"` | Output filename |
| `changefreq` | string | `"weekly"` | Default change frequency |
| `priority` | float | `0.5` | Default page priority (0.0–1.0) |

### Change Frequency Values

| Value | Description |
|-------|-------------|
| `always` | Changes every access |
| `hourly` | Changes hourly |
| `daily` | Changes daily |
| `weekly` | Changes weekly |
| `monthly` | Changes monthly |
| `yearly` | Changes yearly |
| `never` | Archived content |

## Robots.txt

Control search engine crawler access.

```toml
[robots]
enabled = true
filename = "robots.txt"
rules = [
  { user_agent = "*", disallow = ["/admin", "/private"] },
  { user_agent = "GPTBot", disallow = ["/"] },
  { user_agent = "Googlebot", allow = ["/"] }
]
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable robots.txt generation |
| `filename` | string | `"robots.txt"` | Output filename |
| `rules` | array | `[]` | Array of rule objects |

### Rule Object

| Field | Type | Description |
|-------|------|-------------|
| `user_agent` | string | Bot identifier (`*` for all bots) |
| `disallow` | array | Paths to block |
| `allow` | array | Paths to explicitly allow (optional) |

### Common User Agents

| Bot | User Agent |
|-----|------------|
| All bots | `*` |
| Google | `Googlebot` |
| Bing | `Bingbot` |
| OpenAI | `GPTBot` |
| Anthropic | `anthropic-ai` |
| Google Images | `Googlebot-Image` |
| Common Crawl | `CCBot` |

## LLMs.txt

Provide instructions for AI and LLM crawlers.

```toml
[llms]
enabled = true
filename = "llms.txt"
instructions = "This is documentation for Hwaro. Content is MIT licensed."
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable llms.txt generation |
| `filename` | string | `"llms.txt"` | Output filename |
| `instructions` | string | `""` | Instructions for AI crawlers |

## RSS/Atom Feeds

Generate syndication feeds for content updates.

```toml
[feeds]
enabled = true
type = "rss"
filename = "rss.xml"
truncate = 500
limit = 20
sections = ["blog", "news"]
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable feed generation |
| `type` | string | `"rss"` | Feed format: `rss` or `atom` |
| `filename` | string | auto | Output filename |
| `truncate` | int | `0` | Truncate content to N characters (0 = full) |
| `limit` | int | `10` | Maximum items in feed |
| `sections` | array | `[]` | Limit to specific sections (empty = all) |

### Feed Types

| Type | Format | MIME Type |
|------|--------|-----------|
| `rss` | RSS 2.0 | `application/rss+xml` |
| `atom` | Atom 1.0 | `application/atom+xml` |

## OpenGraph & Twitter Cards

Configure social sharing meta tags.

```toml
[og]
default_image = "/images/og-default.png"
type = "article"
twitter_card = "summary_large_image"
twitter_site = "@yourusername"
twitter_creator = "@authorusername"
fb_app_id = "your_fb_app_id"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_image` | string | `""` | Default image for social sharing |
| `type` | string | `"website"` | OpenGraph type |
| `twitter_card` | string | `"summary"` | Twitter card type |
| `twitter_site` | string | `""` | Twitter @username for site |
| `twitter_creator` | string | `""` | Twitter @username for author |
| `fb_app_id` | string | `""` | Facebook App ID |

### OpenGraph Types

| Type | Use Case |
|------|----------|
| `website` | General website, homepage |
| `article` | Blog posts, news articles |
| `profile` | Personal profile pages |
| `product` | Product pages |

### Twitter Card Types

| Type | Description |
|------|-------------|
| `summary` | Small card with square thumbnail |
| `summary_large_image` | Large card with prominent image |
| `player` | Video/audio player |

### Template Variables

Use these in your templates:

| Variable | Description |
|----------|-------------|
| `og_tags` | OpenGraph meta tags only |
| `twitter_tags` | Twitter Card meta tags only |
| `og_all_tags` | Both OG and Twitter tags |

## Auto Includes

Automatically include CSS and JS files from static directories.

```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable auto includes |
| `dirs` | array | `[]` | Directories under `static/` to scan |

### File Ordering

Files are included alphabetically. Use numeric prefixes to control order:

```
static/
└── assets/
    ├── css/
    │   ├── 01-reset.css
    │   ├── 02-typography.css
    │   └── 03-layout.css
    └── js/
        ├── 01-utils.js
        └── 02-app.js
```

### Template Variables

| Variable | Description |
|----------|-------------|
| `auto_includes_css` | CSS `<link>` tags (for `<head>`) |
| `auto_includes_js` | JS `<script>` tags (for before `</body>`) |
| `auto_includes` | Both CSS and JS tags |

## Build Hooks

Run custom shell commands before and after the build process.

```toml
[build]
hooks.pre = ["npm install", "npx tsc"]
hooks.post = ["npm run minify", "./scripts/deploy.sh"]
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hooks.pre` | array | `[]` | Commands to run before build |
| `hooks.post` | array | `[]` | Commands to run after build |

### Behavior

- Commands execute sequentially in order defined
- Pre-hook failure **aborts** the build
- Post-hook failure shows a warning but **doesn't fail** the build
- Hooks run for both `hwaro build` and `hwaro serve`
- In serve mode, hooks re-run on each rebuild

### Example Use Cases

```toml
[build]
hooks.pre = ["npm ci", "npx tsc"]

[build]
hooks.post = [
  "npx imagemin public/images/* --out-dir=public/images",
  "rsync -av public/ server:/var/www/"
]
```

## Complete Example

A comprehensive `config.toml` with all features:

```toml
title = "My Documentation"
description = "Complete project documentation"
base_url = "https://docs.example.com"

[plugins]
processors = ["markdown"]

[highlight]
enabled = true
theme = "github-dark"
use_cdn = true

[markdown]
safe = false

[search]
enabled = true
format = "fuse_json"
fields = ["title", "content", "tags", "description"]
filename = "search.json"

[[taxonomies]]
name = "tags"
feed = true
paginate_by = 20

[[taxonomies]]
name = "categories"
feed = false

[[taxonomies]]
name = "authors"

[sitemap]
enabled = true
changefreq = "weekly"
priority = 0.5

[robots]
enabled = true
rules = [
  { user_agent = "*", disallow = ["/admin", "/preview"] },
  { user_agent = "GPTBot", disallow = ["/"] }
]

[llms]
enabled = true
instructions = "Documentation for My Project. MIT licensed."

[feeds]
enabled = true
type = "rss"
limit = 20
sections = ["blog"]

[og]
default_image = "/images/og-default.png"
type = "article"
twitter_card = "summary_large_image"
twitter_site = "@myproject"

[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]

[build]
hooks.pre = ["npm install"]
hooks.post = ["npm run optimize"]
```

## See Also

- [Configuration Guide](/getting-started/configuration/) — Introduction to configuration
- [CLI Reference](/reference/cli/) — Command-line options that override config
- [Front Matter Reference](/reference/front-matter/) — Page-level settings