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
footnotes = false
task_lists = false
definition_lists = false
mermaid = false
math = false
math_engine = "katex"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| safe | bool | false | Strip raw HTML from markdown |
| lazy_loading | bool | false | Automatically add `loading="lazy"` to images |
| emoji | bool | false | Convert emoji shortcodes (e.g. `:smile:`) to emoji characters |
| footnotes | bool | false | Enable footnote syntax (`[^1]`) |
| task_lists | bool | false | Enable task list syntax (`- [ ]` / `- [x]`) |
| definition_lists | bool | false | Enable definition list syntax (`Term\n: Definition`) |
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
filename = "sitemap.xml"
changefreq = "weekly"
priority = 0.5
exclude = ["/private", "/drafts"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable sitemap generation |
| filename | string | "sitemap.xml" | Output filename |
| changefreq | string | "weekly" | Default change frequency (`always`, `hourly`, `daily`, `weekly`, `monthly`, `yearly`, `never`) |
| priority | float | 0.5 | Default priority (0.0 to 1.0) |
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
twitter_creator = "@authorname"
fb_app_id = "your_fb_app_id"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| default_image | string | — | Fallback image when page has none |
| type | string | "article" | OpenGraph type (`website`, `article`) |
| twitter_card | string | "summary_large_image" | Twitter card type (`summary`, `summary_large_image`) |
| twitter_site | string | — | Site's Twitter handle |
| twitter_creator | string | — | Author's Twitter handle |
| fb_app_id | string | — | Facebook App ID |

See [SEO](/features/seo/) for template usage and output examples.

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
tokenize_cjk = false
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Generate search index |
| format | string | "fuse_json" | Search index format |
| fields | array | ["title", "content"] | Fields to include in index |
| filename | string | "search.json" | Output filename |
| exclude | array | [] | Exclude paths (prefixes) from search index |
| tokenize_cjk | bool | false | Enable CJK bigram tokenization for search |

## Pagination

Site-level pagination defaults. These apply when sections enable pagination via front matter.

```toml
[pagination]
enabled = false
per_page = 10
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable pagination globally |
| per_page | int | 10 | Default items per page |

See [Pagination](/features/pagination/) for section-level configuration and template usage.

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
footnotes = true
task_lists = true

[permalinks]
"old/posts" = "posts"

[feeds]
enabled = true
limit = 20

[sitemap]
enabled = true
changefreq = "weekly"
priority = 0.5

[pagination]
enabled = false
per_page = 10

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
twitter_creator = "@myblog"

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
