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
emoji = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| safe | bool | false | Strip raw HTML from markdown |
| lazy_loading | bool | false | Automatically add `loading="lazy"` to images |
| emoji | bool | false | Convert emoji shortcodes (e.g. `:smile:`) to emoji characters |

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
type = "rss"
limit = 20
truncate = 0
filename = "feed.xml"
sections = []
default_language_only = true   # true: main feed = default language only, false: all languages
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable feed generation |
| type | string | "rss" | Feed format (`"rss"` or `"atom"`) |
| limit | int | 10 | Maximum number of items in the feed |
| truncate | int | 0 | Truncate content to N characters (0 = no truncation) |
| filename | string | "" | Output filename (auto-determined if empty) |
| sections | array | [] | Limit feed to specific sections |
| default_language_only | bool | true | Only include default language in main feed |

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

[[robots.rules]]
user_agent = "*"
allow = ["/"]
disallow = ["/private"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | true | Enable robots.txt generation |
| filename | string | "robots.txt" | Output filename |
| rules | array | [] | List of robot rules |

Each rule in `rules` supports:

| Key | Type | Description |
|-----|------|-------------|
| user_agent | string | User-agent to match (e.g. `"*"`, `"Googlebot"`) |
| allow | array | Paths to allow |
| disallow | array | Paths to disallow |

### OpenGraph

```toml
[og]
default_image = "/images/og.png"
type = "website"
twitter_card = "summary_large_image"
twitter_site = "@username"
```

## LLMs.txt

Generate instruction files for AI/LLM crawlers:

```toml
[llms]
enabled = true
filename = "llms.txt"
instructions = "This site's content is provided under the MIT license."
full_enabled = true
full_filename = "llms-full.txt"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Generate `llms.txt` |
| filename | string | "llms.txt" | Output filename |
| instructions | string | "" | Instructions text for LLM crawlers |
| full_enabled | bool | false | Generate full content version (`llms-full.txt`) |
| full_filename | string | "llms-full.txt" | Full version filename |

See [LLMs.txt](/features/llms-txt/) for details.

## Search

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content"]
filename = "search.json"
exclude = ["/private", "/drafts"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Generate search index |
| format | string | "fuse_json" | Search index format |
| fields | array | ["title", "content"] | Fields to include in index |
| filename | string | "search.json" | Output filename |
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
theme = "github-dark"
use_cdn = true
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

[languages.en]
language_name = "English"
weight = 1

[languages.ko]
language_name = "한국어"
weight = 2
generate_feed = true
build_search_index = true
taxonomies = ["tags", "categories"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| default_language | string | "en" | Default language code |
| language_name | string | — | Human-readable language name |
| weight | int | 0 | Sort order (lower = first) |
| generate_feed | bool | false | Generate RSS feed for this language |
| build_search_index | bool | false | Include in search index |
| taxonomies | array | [] | Taxonomies for this language |

See [Multilingual](/features/multilingual/) for content structure and template usage.

## Deployment

Configure deployment targets for the `hwaro deploy` command.

```toml
[deployment]
confirm = false
dry_run = false
force = false
max_deletes = 256
source_dir = "public"

[[deployment.targets]]
name = "prod"
url = "file:///var/www/mysite"

[[deployment.targets]]
name = "s3"
url = "s3://your-bucket"
command = "aws s3 sync {source}/ {url} --delete"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| confirm | bool | false | Ask for confirmation before deploying |
| dry_run | bool | false | Show changes without writing |
| force | bool | false | Force upload (ignore file comparisons) |
| max_deletes | int | 256 | Maximum deletions allowed (-1 to disable) |
| source_dir | string | "public" | Source directory to deploy |

### Target Options

| Key | Type | Description |
|-----|------|-------------|
| name | string | Target identifier |
| url | string | Destination URL or path |
| command | string | Custom deploy command (overrides URL-based deployment) |
| include | string | Glob pattern for files to include |
| exclude | string | Glob pattern for files to exclude |
| strip_index_html | bool | Remove `index.html` from paths |

Custom commands support placeholders: `{source}`, `{url}`, `{target}`.

## Content Files

Publish non-Markdown files from `content/` to the output directory:

```toml
[content.files]
allow_extensions = ["jpg", "jpeg", "png", "gif", "svg", "webp", "pdf"]
disallow_extensions = ["psd", "ai"]
disallow_paths = ["drafts/**", "**/_*"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| allow_extensions | array | [] | File extensions to publish |
| disallow_extensions | array | [] | File extensions to exclude |
| disallow_paths | array | [] | Glob patterns for paths to exclude |

See [Content Files](/features/content-files/) for details.

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
lazy_loading = true
emoji = false

[permalinks]
"old/posts" = "posts"

[feeds]
enabled = true
limit = 20

[sitemap]
enabled = true

[robots]
enabled = true

[llms]
enabled = true
instructions = "Content under MIT license."
full_enabled = true

[og]
default_image = "/images/og-default.png"
twitter_card = "summary_large_image"
twitter_site = "@myblog"

[search]
enabled = true
format = "fuse_json"
fields = ["title", "content"]

[highlight]
enabled = true
theme = "github-dark"
use_cdn = true

[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]

[content.files]
allow_extensions = ["jpg", "jpeg", "png", "gif", "svg", "webp"]

[[taxonomies]]
name = "tags"
feed = true

[[taxonomies]]
name = "categories"

[deployment]
source_dir = "public"

[[deployment.targets]]
name = "prod"
url = "file:///var/www/myblog"
```

## See Also

- [Features](/features/) — All built-in features
- [CLI](/start/cli/) — Command-line options that override config
- [Multilingual](/features/multilingual/) — Multilingual configuration details
- [LLMs.txt](/features/llms-txt/) — LLM instructions configuration
- [Build Hooks](/features/build-hooks/) — Pre/post build commands
