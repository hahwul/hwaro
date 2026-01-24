+++
title = "Configuration"
toc = true
+++

Site configuration is defined in `config.toml`.

## Basic Settings

```toml
title = "My Site"
description = "Site description"
base_url = "https://example.com"
```

## Syntax Highlighting

```toml
[highlight]
enabled = true
theme = "github-dark"
use_cdn = true
```

Themes: `github`, `github-dark`, `monokai`, `atom-one-dark`, `vs2015`, `nord`, `dracula`

## Search

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content", "tags", "description"]
filename = "search.json"
```

## Taxonomies

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate_by = 10

[[taxonomies]]
name = "categories"
```

## Sitemap

```toml
[sitemap]
enabled = true
changefreq = "weekly"
priority = 0.5
```

## Robots.txt

```toml
[robots]
enabled = true
rules = [
  { user_agent = "*", disallow = ["/admin"] },
  { user_agent = "GPTBot", disallow = ["/"] }
]
```

## RSS/Atom Feeds

```toml
[feeds]
enabled = true
type = "rss"           # or "atom"
limit = 20
sections = ["blog"]    # empty = all sections
```

## OpenGraph & Twitter

```toml
[og]
default_image = "/images/og.png"
type = "article"
twitter_card = "summary_large_image"
twitter_site = "@username"
```

## Auto Includes

Auto-load CSS/JS files from static directories:

```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]
```

Files are included alphabetically. Use prefixes for ordering: `01-reset.css`, `02-main.css`.

## Build Hooks

```toml
[build]
hooks.pre = ["npm install"]
hooks.post = ["npm run minify"]
```

## Markdown

```toml
[markdown]
safe = false    # true = strip raw HTML
```

## LLMs.txt

```toml
[llms]
enabled = true
instructions = "Content is MIT licensed."
```

## Content Files

Publish non-Markdown files from `content/` into the output directory (preserving paths).

```toml
[content.files]
allow_extensions = ["jpg", "png", "svg", "pdf"]
disallow_extensions = ["psd"]
disallow_paths = ["private/**", "**/_*"]
```

Example: `content/about/profile.jpg` → `/about/profile.jpg`
