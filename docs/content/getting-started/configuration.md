+++
title = "Configuration"
description = "Learn how to configure your Hwaro site with config.toml"
toc = true
+++


Hwaro uses a TOML configuration file (`config.toml`) in your project root. This guide covers all available configuration options.

## Basic Configuration

The minimum configuration requires just a few fields:

```toml
title = "My Site"
description = "A brief description of your site"
base_url = "https://example.com"
```

**Options:**

- `title` (string): Your site's title, used in templates and meta tags
- `description` (string): Site description for SEO and meta tags
- `base_url` (string): Production URL of your site (no trailing slash)

## Plugins

Configure which content processors to use:

```toml
[plugins]
processors = ["markdown"]
```

**Options:**

- `processors` (array, default: `["markdown"]`): List of content processors to enable

## Syntax Highlighting

Configure code block syntax highlighting using Highlight.js:

```toml
[highlight]
enabled = true
theme = "github-dark"
use_cdn = true
```

**Options:**

- `enabled` (bool, default: `false`): Enable syntax highlighting
- `theme` (string, default: `"github"`): Highlight.js theme name
- `use_cdn` (bool, default: `true`): Use CDN for Highlight.js assets

Available themes include: `github`, `github-dark`, `monokai`, `atom-one-dark`, `vs2015`, `nord`, and many more.

## Markdown

Configure markdown parsing behavior:

```toml
[markdown]
safe = false
```

**Options:**

- `safe` (bool, default: `false`): If true, raw HTML in markdown is stripped

When `safe` is enabled, any raw HTML in your markdown files will be replaced with `<!-- raw HTML omitted -->` comments.

## Search

Generate a client-side search index (Fuse.js compatible):

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content", "tags", "description"]
filename = "search.json"
```

**Options:**

- `enabled` (bool, default: `false`): Enable search index generation
- `format` (string, default: `"fuse_json"`): Index format (currently only `fuse_json`)
- `fields` (array, default: `["title"]`): Fields to include in the index
- `filename` (string, default: `"search.json"`): Output filename

Available fields: `title`, `content`, `tags`, `url`, `section`, `description`

## Taxonomies

Define content classification systems:

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate_by = 10

[[taxonomies]]
name = "categories"
feed = false

[[taxonomies]]
name = "authors"
```

**Options:**

- `name` (string, required): Taxonomy name (used in URLs and front matter)
- `feed` (bool, default: `false`): Generate RSS feed for this taxonomy
- `paginate_by` (int, default: `0`): Items per page (0 = no pagination)
- `sitemap` (bool, default: `true`): Include in sitemap

## SEO: Sitemap

Generate a sitemap.xml for search engines:

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
- `priority` (float, default: `0.5`): Default page priority (0.0-1.0)

## SEO: Robots.txt

Control search engine crawler access:

```toml
[robots]
enabled = true
filename = "robots.txt"
rules = [
  { user_agent = "*", disallow = ["/admin", "/private"] },
  { user_agent = "GPTBot", disallow = ["/"] }
]
```

**Options:**

- `enabled` (bool, default: `false`): Enable robots.txt generation
- `filename` (string, default: `"robots.txt"`): Output filename
- `rules` (array, default: `[]`): Array of rule objects

## SEO: LLMs.txt

Provide instructions for AI/LLM crawlers:

```toml
[llms]
enabled = true
filename = "llms.txt"
instructions = "Do not use for AI training without permission."
```

**Options:**

- `enabled` (bool, default: `false`): Enable llms.txt generation
- `filename` (string, default: `"llms.txt"`): Output filename
- `instructions` (string, default: `""`): Instructions for AI crawlers

## RSS/Atom Feeds

Generate syndication feeds:

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
- `type` (string, default: `"rss"`): Feed type: `rss` or `atom`
- `filename` (string, default: auto): Output filename (auto-generated if empty)
- `truncate` (int, default: `0`): Truncate content to N characters (0 = full)
- `limit` (int, default: `10`): Maximum items in feed
- `sections` (array, default: `[]`): Limit to specific sections (empty = all)

## OpenGraph & Twitter Cards

Configure social sharing meta tags:

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

## Auto Includes

Automatically include CSS/JS files from static directories:

```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]
```

**Options:**

- `enabled` (bool, default: `false`): Enable auto includes
- `dirs` (array, default: `[]`): Directories under `static/` to scan

Files are included alphabetically. Use numeric prefixes to control order:

```
static/
├── assets/
│   ├── css/
│   │   ├── 01-reset.css
│   │   ├── 02-main.css
│   └── js/
│       ├── 01-utils.js
│       └── 02-app.js
```

## Build Hooks

Run custom shell commands before and after builds:

```toml
[build]
hooks.pre = ["npm install", "npx tsc"]
hooks.post = ["npm run minify", "./scripts/deploy.sh"]
```

**Options:**

- `hooks.pre` (array, default: `[]`): Commands to run before build
- `hooks.post` (array, default: `[]`): Commands to run after build

- Pre-hooks run sequentially; failure aborts the build
- Post-hooks run sequentially; failure shows a warning but doesn't fail the build
- Hooks are executed for both `build` and `serve` commands

## Complete Example

Here's a comprehensive configuration example:

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
fields = ["title", "content", "tags"]
filename = "search.json"

[[taxonomies]]
name = "tags"
feed = true

[[taxonomies]]
name = "categories"
paginate_by = 10

[sitemap]
enabled = true
changefreq = "weekly"
priority = 0.5

[robots]
enabled = true
rules = [
  { user_agent = "*", disallow = ["/admin"] }
]

[feeds]
enabled = true
type = "rss"
limit = 20

[og]
default_image = "/images/og-default.png"
type = "article"
twitter_card = "summary_large_image"

[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]

[build]
hooks.pre = ["npm install"]
hooks.post = ["npm run optimize"]
```

## Next Steps

- Learn about [Content Management](/guide/content-management/) to organize your content
- Explore [Templates](/guide/templates/) to customize your site's appearance
- See the [Configuration Reference](/reference/config/) for complete details