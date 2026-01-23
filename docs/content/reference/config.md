+++
title = "Configuration Reference"
description = "Complete reference for all Hwaro configuration options"
toc = true
+++


This is the complete reference for all options available in `config.toml`. For a guided introduction, see [Configuration](/getting-started/configuration/).

## Site Settings

Basic site metadata used throughout your site and in meta tags.

```toml
title = "My Site"
description = "A brief description of your site"
base_url = "https://example.com"
```

**Options:**

- `title` (string, required): Site title, used in templates and meta tags
- `description` (string): Site description for SEO and social sharing
- `base_url` (string, required): Production URL without trailing slash

## Plugins

Configure content processors and extensions.

```toml
[plugins]
processors = ["markdown"]
```

**Options:**

- `processors` (array, default: `["markdown"]`): List of content processors to enable

**Available Processors:**

- `markdown` — Process Markdown files with TOML front matter

## Syntax Highlighting

Configure code block syntax highlighting using Highlight.js.

```toml
[highlight]
enabled = true
theme = "github-dark"
use_cdn = true
```

**Options:**

- `enabled` (bool, default: `false`): Enable syntax highlighting
- `theme` (string, default: `"github"`): Highlight.js theme name
- `use_cdn` (bool, default: `true`): Load Highlight.js from CDN

**Popular Themes:**

- `github` — GitHub light theme
- `github-dark` — GitHub dark theme
- `monokai` — Monokai dark theme
- `atom-one-dark` — Atom One Dark theme
- `atom-one-light` — Atom One Light theme
- `vs2015` — Visual Studio 2015 dark theme
- `nord` — Nord color palette theme
- `dracula` — Dracula dark theme
- `tomorrow-night` — Tomorrow Night theme

See [Highlight.js demo](https://highlightjs.org/static/demo/) for all themes.

## Markdown

Configure markdown parsing behavior.

```toml
[markdown]
safe = false
```

**Options:**

- `safe` (bool, default: `false`): Strip raw HTML from markdown content

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

**Options:**

- `enabled` (bool, default: `false`): Enable search index generation
- `format` (string, default: `"fuse_json"`): Index format
- `fields` (array, default: `["title"]`): Fields to include in the index
- `filename` (string, default: `"search.json"`): Output filename

**Available Fields:**

- `title` — Page title from front matter
- `content` — Page content (HTML stripped)
- `description` — Page description from front matter
- `tags` — Page tags from front matter
- `url` — Page URL path
- `section` — Section the page belongs to

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

**Options:**

- `name` (string, required): Taxonomy name (used in URLs and front matter)
- `feed` (bool, default: `false`): Generate RSS feed for each term
- `paginate_by` (int, default: `0`): Items per page (0 = no pagination)
- `sitemap` (bool, default: `true`): Include taxonomy pages in sitemap

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

**Options:**

- `enabled` (bool, default: `false`): Enable sitemap generation
- `filename` (string, default: `"sitemap.xml"`): Output filename
- `changefreq` (string, default: `"weekly"`): Default change frequency
- `priority` (float, default: `0.5`): Default page priority (0.0–1.0)

**Change Frequency Values:**

- `always` — Changes every access
- `hourly` — Changes hourly
- `daily` — Changes daily
- `weekly` — Changes weekly
- `monthly` — Changes monthly
- `yearly` — Changes yearly
- `never` — Archived content

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

**Options:**

- `enabled` (bool, default: `false`): Enable robots.txt generation
- `filename` (string, default: `"robots.txt"`): Output filename
- `rules` (array, default: `[]`): Array of rule objects

**Rule Object Fields:**

- `user_agent` (string): Bot identifier (`*` for all bots)
- `disallow` (array): Paths to block
- `allow` (array): Paths to explicitly allow (optional)

**Common User Agents:**

- `*` — All bots
- `Googlebot` — Google
- `Bingbot` — Bing
- `GPTBot` — OpenAI
- `anthropic-ai` — Anthropic
- `Googlebot-Image` — Google Images
- `CCBot` — Common Crawl

## LLMs.txt

Provide instructions for AI and LLM crawlers.

```toml
[llms]
enabled = true
filename = "llms.txt"
instructions = "This is documentation for Hwaro. Content is MIT licensed."
```

**Options:**

- `enabled` (bool, default: `false`): Enable llms.txt generation
- `filename` (string, default: `"llms.txt"`): Output filename
- `instructions` (string, default: `""`): Instructions for AI crawlers

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

**Options:**

- `enabled` (bool, default: `false`): Enable feed generation
- `type` (string, default: `"rss"`): Feed format: `rss` or `atom`
- `filename` (string, default: auto): Output filename
- `truncate` (int, default: `0`): Truncate content to N characters (0 = full)
- `limit` (int, default: `10`): Maximum items in feed
- `sections` (array, default: `[]`): Limit to specific sections (empty = all)

**Feed Types:**

- `rss` — RSS 2.0 format (`application/rss+xml`)
- `atom` — Atom 1.0 format (`application/atom+xml`)

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

**Options:**

- `default_image` (string, default: `""`): Default image for social sharing
- `type` (string, default: `"website"`): OpenGraph type
- `twitter_card` (string, default: `"summary"`): Twitter card type
- `twitter_site` (string, default: `""`): Twitter @username for site
- `twitter_creator` (string, default: `""`): Twitter @username for author
- `fb_app_id` (string, default: `""`): Facebook App ID

**OpenGraph Types:**

- `website` — General website, homepage
- `article` — Blog posts, news articles
- `profile` — Personal profile pages
- `product` — Product pages

**Twitter Card Types:**

- `summary` — Small card with square thumbnail
- `summary_large_image` — Large card with prominent image
- `player` — Video/audio player

**Template Variables:**

- `og_tags` — OpenGraph meta tags only
- `twitter_tags` — Twitter Card meta tags only
- `og_all_tags` — Both OG and Twitter tags

## Auto Includes

Automatically include CSS and JS files from static directories.

```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]
```

**Options:**

- `enabled` (bool, default: `false`): Enable auto includes
- `dirs` (array, default: `[]`): Directories under `static/` to scan

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

**Template Variables:**

- `auto_includes_css` — CSS `<link>` tags (for `<head>`)
- `auto_includes_js` — JS `<script>` tags (for before `</body>`)
- `auto_includes` — Both CSS and JS tags

## Build Hooks

Run custom shell commands before and after the build process.

```toml
[build]
hooks.pre = ["npm install", "npx tsc"]
hooks.post = ["npm run minify", "./scripts/deploy.sh"]
```

**Options:**

- `hooks.pre` (array, default: `[]`): Commands to run before build
- `hooks.post` (array, default: `[]`): Commands to run after build

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