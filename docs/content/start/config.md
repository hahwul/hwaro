+++
title = "Configuration"
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

## Build Options

```toml
[build]
output_dir = "public"
drafts = false
parallel = true
cache = false
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| output_dir | string | "public" | Output directory |
| drafts | bool | false | Include draft content |
| parallel | bool | true | Parallel processing |
| cache | bool | false | Enable build caching |

### Build Hooks

Run commands before/after build:

```toml
[build]
hooks.pre = ["npm install", "npx tsc"]
hooks.post = ["npm run minify"]
```

## Markdown

```toml
[markdown]
safe = false
lazy_loading = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| safe | bool | false | Strip raw HTML from markdown |
| lazy_loading | bool | false | Automatically add `loading="lazy"` to images |

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

## SEO

### Feeds

```toml
[feeds]
enabled = true
limit = 20
```

### Sitemap

```toml
[sitemap]
enabled = true
exclude = ["/private", "/drafts"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable sitemap generation |
| exclude | array | [] | Exclude paths (prefixes) from sitemap |

### Robots.txt

```toml
[robots]
enabled = true
```

### OpenGraph

```toml
[og]
default_image = "/images/og.png"
type = "website"
twitter_card = "summary_large_image"
twitter_site = "@username"
```

## Search

```toml
[search]
enabled = true
include_content = true
exclude = ["/private", "/drafts"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Generate search index |
| include_content | bool | true | Include content in index |
| exclude | array | [] | Exclude paths (prefixes) from search index |

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

## Syntax Highlighting

```toml
[highlight]
enabled = true
theme = "monokai"
line_numbers = false
```

## Auto Includes

Automatically include CSS/JS from static directories:

```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]
```

## Multilingual

```toml
default_language = "en"

[[languages]]
code = "en"
name = "English"

[[languages]]
code = "ko"
name = "한국어"
```

## Deployment

Configure deployment targets for the `hwaro deploy` command.

```toml
[deployment]
target = "prod" # Default target

[[deployment.targets]]
name = "prod"
url = "file://./out"

[[deployment.targets]]
name = "s3"
url = "s3://your-bucket"
command = "aws s3 sync {source}/ {url} --delete"
```

## Full Example

```toml
title = "My Blog"
description = "A blog about programming"
base_url = "https://myblog.com"
default_language = "en"

[build]
output_dir = "public"
drafts = false
parallel = true
hooks.pre = ["npm ci"]
hooks.post = ["npm run optimize"]

[markdown]
safe = false

[feeds]
enabled = true
limit = 20

[sitemap]
enabled = true

[robots]
enabled = true

[og]
default_image = "/images/og-default.png"
twitter_card = "summary_large_image"
twitter_site = "@myblog"

[search]
enabled = true
include_content = true
exclude = ["/private"]

[highlight]
enabled = true
theme = "monokai"

[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]

[[taxonomies]]
name = "tags"
feed = true

[[taxonomies]]
name = "categories"
```

## Environment-Specific Config

For different environments, use separate config files:

```bash
hwaro build --config config.production.toml
```
