+++
title = "SEO"
description = "Built-in sitemaps, RSS feeds, robots.txt, and social sharing meta tags"
weight = 1
+++

Hwaro includes built-in SEO features: sitemaps, RSS feeds, robots.txt, and social sharing meta tags.

## Sitemap

Automatically generates `sitemap.xml` for search engines.

### Configuration

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
| enabled | bool | false | Generate `sitemap.xml` |
| filename | string | "sitemap.xml" | Output filename |
| changefreq | string | "weekly" | Default change frequency for all pages |
| priority | float | 0.5 | Default priority for all pages (0.0 to 1.0) |
| exclude | array | [] | Path prefixes to exclude (e.g., `["/private"]` excludes `/private`, `/private/page.html`) |

### Output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://example.com/</loc>
    <lastmod>2024-01-15</lastmod>
  </url>
  <url>
    <loc>https://example.com/about/</loc>
  </url>
</urlset>
```

### Excluding Pages

Set `in_sitemap = false` in front matter:

```markdown
+++
title = "Private Page"
in_sitemap = false
+++
```

---

## RSS Feeds

Generate RSS feeds for your site and sections.

### Configuration

```toml
[feeds]
enabled = true
type = "rss"              # "rss" or "atom"
limit = 20                # Maximum number of items
truncate = 0              # Truncate to N characters (0 = no truncation)
full_content = true       # true = full HTML body, false = description/summary only
filename = ""             # Leave empty for default (rss.xml or atom.xml)
sections = []             # Limit to specific sections, e.g., ["posts"]
```

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `false` | Enable feed generation |
| `type` | `"rss"` | Feed format: `"rss"` or `"atom"` |
| `limit` | `10` | Maximum number of items in feed |
| `truncate` | `0` | Truncate content to N characters (0 = full content) |
| `full_content` | `true` | `true` = full HTML in feed, `false` = use front matter `description` or auto-generated summary |
| `filename` | `""` | Custom filename (empty = `rss.xml` or `atom.xml`) |
| `sections` | `[]` | Limit feed to specific sections |
| `default_language_only` | `true` | Multilingual: main feed includes default language only |

### Section Feeds

Enable per-section feeds:

```markdown
+++
title = "Blog"
generate_feeds = true
+++
```

Generates `/blog/rss.xml`.

### Output

- `/rss.xml` — Site-wide feed
- `/blog/rss.xml` — Section feed (if enabled)

### Multilingual Feeds

When the site is multilingual, feeds are generated per language automatically:

| Language | Feed Path | Contents |
|----------|-----------|----------|
| Default (e.g., `en`) | `/rss.xml` | Default language pages only (configurable) |
| Non-default (e.g., `ko`) | `/ko/rss.xml` | Only Korean pages |
| Non-default (e.g., `ja`) | `/ja/rss.xml` | Only Japanese pages |

By default, the main site feed includes **only default language pages** (`default_language_only = true`). Set `default_language_only = false` to include all languages in the main feed. Each non-default language with `generate_feed = true` gets its own separate feed regardless of this setting.

```toml
[feeds]
enabled = true
default_language_only = true   # true (default): main feed = default language only
                               # false: main feed includes all languages
```

Per-language feed control:

```toml
[languages.ko]
language_name = "한국어"
generate_feed = true    # Generates /ko/rss.xml (default: true)

[languages.ja]
language_name = "日本語"
generate_feed = false   # No /ja/rss.xml will be generated
```

Language feeds share the same `sections`, `limit`, `truncate`, and `full_content` settings from `[feeds]` config. RSS language feeds include a `<language>` tag, and Atom feeds include an `xml:lang` attribute. The feed title includes the language name (e.g., `"My Site (한국어)"`).

### Custom Feed Templates

To take full control of the feed markup, create a template named after the feed output:

| Feed type | Template file | Loaded as key |
|-----------|---------------|---------------|
| RSS | `templates/rss.xml.jinja` | `rss.xml` |
| Atom | `templates/atom.xml.jinja` | `atom.xml` |

Any template extension works (`.jinja`, `.j2`, `.jinja2`, `.html`) — only the final extension is stripped, so `rss.xml.jinja` loads under the key `rss.xml`. Whatever the extension, the file is always rendered as **Jinja** (an `.ecr` file is picked up too, but ECR `<%= %>` tags pass through as literal text — use Jinja syntax). The template file itself is the opt-in: when it's absent, Hwaro emits its built-in feed exactly as before, and deleting the template falls back to the built-in output. The override applies to **all four feed kinds** — the main feed, per-section feeds, per-language feeds, and per-taxonomy-term feeds — and a custom `[feeds] filename` still controls the output path.

`{% include %}` works inside feed templates, and a broken template fails the build with a template error naming the file.

#### Context variables

`feed` — metadata about the feed being rendered:

| Variable | Type | Description |
|----------|------|-------------|
| `feed.type` | string | `"rss"` or `"atom"` (follows `[feeds] type`) |
| `feed.kind` | string | `"main"`, `"section"`, `"language"`, or `"taxonomy"` |
| `feed.title` | string | Feed title (site title, `Site - Section`, `Site (한국어)`, …) |
| `feed.description` | string | Site description |
| `feed.url` | string | Absolute, percent-encoded self URL of this feed file |
| `feed.home_url` | string | Canonical HTML URL the feed represents (site root, section page, or language home) |
| `feed.base_url` | string | `base_url` without a trailing slash |
| `feed.language` | string? | Language code for per-language feeds, else none |
| `feed.updated` | time | Newest entry date (deterministic; epoch when no entry has a date) |
| `feed.updated_rfc3339` | string | `feed.updated` as RFC 3339 (Atom `<updated>`) |
| `feed.updated_rfc822` | string | `feed.updated` as RFC 822 (RSS `<lastBuildDate>`/`<pubDate>` style) |
| `feed.author` | string | Site title (falls back to the feed title) |
| `feed.section_url` | string? | Section URL — section feeds only |
| `feed.taxonomy` / `feed.term` | string? | Taxonomy name and term — taxonomy feeds only |

`pages` — the sorted, limit-applied entry list. Each entry:

| Variable | Type | Description |
|----------|------|-------------|
| `title` | string | Page title (site title when the page title is empty) |
| `url` | string | Absolute, percent-encoded page URL |
| `date` / `updated` | time? | Raw front-matter dates (usable with the `date` filter) |
| `date_rfc822` | string? | Preformatted RFC 822 date; none for dateless pages |
| `updated_rfc3339` | string | RFC 3339 timestamp from `updated`/`date` (epoch fallback) |
| `description` | string? | Front-matter description |
| `summary` | string | Plain-text summary (description → `<!-- more -->` summary → excerpt) |
| `content` | string | Body honoring `full_content`/`truncate` (plain text when truncating) |
| `content_html` | string | Full HTML body with links absolutized for out-of-context readers |
| `content_is_html` | bool | Whether `content` is HTML (`false` under `truncate`/`full_content = false`) |
| `authors` | array | Front-matter authors |
| `categories` | array | Taxonomy terms — `tags` first, then other taxonomies, deduplicated |
| `section` | string | Page section path |
| `language` | string? | Page language code |

#### Example

Values are **not** pre-escaped — applying `xml_escape` (or emitting CDATA) is the template author's job:

```jinja
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>{{ feed.title | xml_escape }}</title>
    <link>{{ feed.home_url | xml_escape }}</link>
    <description>{{ feed.description | xml_escape }}</description>
    {% if feed.language %}<language>{{ feed.language | xml_escape }}</language>{% endif %}
    <atom:link href="{{ feed.url | xml_escape }}" rel="self" type="application/rss+xml" />
    {% for p in pages %}
    <item>
      <title>{{ p.title | xml_escape }}</title>
      <link>{{ p.url | xml_escape }}</link>
      <guid>{{ p.url | xml_escape }}</guid>
      <description>{{ p.summary | xml_escape }}</description>
      {% if p.date_rfc822 %}<pubDate>{{ p.date_rfc822 }}</pubDate>{% endif %}
      {% for term in p.categories %}<category>{{ term | xml_escape }}</category>{% endfor %}
    </item>
    {% endfor %}
  </channel>
</rss>
```

### Template Links

```jinja
<link rel="alternate" type="application/rss+xml" 
      href="{{ base_url }}/rss.xml" 
      title="{{ site.title }}">

{% if page.language and page.language != "en" %}
<link rel="alternate" type="application/rss+xml"
      href="{{ base_url }}/{{ page.language }}/rss.xml"
      title="{{ site.title }} ({{ page.language }})">
{% endif %}
```

---

## Robots.txt

Control search engine crawling.

### Configuration

```toml
[robots]
enabled = true
```

With custom rules:

```toml
[robots]
enabled = true
rules = [
  { user_agent = "*", disallow = ["/admin", "/private"] },
  { user_agent = "GPTBot", disallow = ["/"] }
]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | true | Generate `robots.txt` |
| filename | string | "robots.txt" | Output filename |
| rules | array | [] | List of user-agent rules with `allow` and `disallow` paths |

When no rules are configured, Hwaro generates a default allow-all rule. If a rule has both `allow` and `disallow` empty, an explicit `Allow: /` is added to prevent ambiguous behavior.

### Output

```
User-agent: *
Allow: /
Sitemap: https://example.com/sitemap.xml
```

---

## LLMs.txt

Generate instruction files for AI/LLM crawlers following the [llms.txt standard](https://llmstxt.org/).

```toml
[llms]
enabled = true
instructions = "This site's content is provided under the MIT license."
full_enabled = true
```

See [LLMs.txt](/features/llms-txt/) for full configuration and output details.

---

## OpenGraph Tags

Social sharing meta tags for Facebook, LinkedIn, etc.

### Configuration

```toml
[og]
default_image = "/images/og-default.png"
type = "website"
fb_app_id = "your_fb_app_id"
```

| Key | Description |
|-----|-------------|
| default_image | Fallback image when page has none |
| type | OpenGraph type for content pages (default: `"article"`; listing pages always emit `"website"`) |
| fb_app_id | Facebook App ID (optional) |

### Page-Level Override

```markdown
+++
title = "My Article"
description = "Article description"
image = "/images/article-cover.png"
+++
```

### Template Usage

```jinja
<head>
  {{ og_tags | safe }}
</head>
```

### Output

```html
<meta property="og:title" content="My Article">
<meta property="og:type" content="article">
<meta property="og:url" content="https://example.com/my-article/">
<meta property="og:description" content="Article description">
<meta property="og:image" content="https://example.com/images/article-cover.png">
```

---

## Twitter Cards

Twitter-specific sharing tags.

### Configuration

```toml
[og]
twitter_card = "summary_large_image"
twitter_site = "@yourusername"
twitter_creator = "@authorusername"
```

| Key | Description |
|-----|-------------|
| twitter_card | Card type: summary, summary_large_image |
| twitter_site | Site's Twitter handle |
| twitter_creator | Author's Twitter handle |

### Template Usage

```jinja
<head>
  {{ twitter_tags | safe }}
</head>
```

Or include both OG and Twitter:

```jinja
<head>
  {{ og_all_tags | safe }}
</head>
```

### Output

```html
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="My Article">
<meta name="twitter:description" content="Article description">
<meta name="twitter:image" content="https://example.com/images/article-cover.png">
<meta name="twitter:site" content="@yourusername">
```

---

## JSON-LD Structured Data

Hwaro automatically generates Article and BreadcrumbList JSON-LD for every page.

```jinja
<head>
  {{ jsonld | safe }}
</head>
```

Additional schema types (FAQ, HowTo, WebSite, Organization) are also available. See [Structured Data](/features/structured-data/) for all types, configuration, and output examples.

---

## Template Variables

### Pre-rendered HTML

These variables output ready-to-use HTML tags:

| Variable | Description |
|----------|-------------|
| og_tags | OpenGraph meta tags |
| twitter_tags | Twitter Card meta tags |
| og_all_tags | Both OG and Twitter tags |
| canonical_tag | Canonical link tag |
| hreflang_tags | Hreflang alternate link tags |
| jsonld | Article + BreadcrumbList JSON-LD |
| jsonld_article | Article JSON-LD only |
| jsonld_breadcrumb | BreadcrumbList JSON-LD only |
| page_description | Page description (fallback: site) |
| page_image | Page image (fallback: og.default_image) |

### Structured SEO Object

The `seo` object provides individual field access for building custom meta tags:

| Property | Type | Description |
|----------|------|-------------|
| seo.canonical_url | String | Full canonical URL |
| seo.og_type | String | OpenGraph type (default: "article") |
| seo.og_image | String | Resolved absolute image URL |
| seo.twitter_card | String | Twitter card type |
| seo.twitter_site | String | Twitter site handle |
| seo.twitter_creator | String | Twitter creator handle |
| seo.fb_app_id | String | Facebook App ID |
| seo.hreflang | Array | Language translation links |

```jinja
<head>
  <link rel="canonical" href="{{ seo.canonical_url }}">
  <meta property="og:title" content="{{ page.title }}">
  <meta property="og:type" content="{{ seo.og_type }}">
  <meta property="og:url" content="{{ seo.canonical_url }}">
  {% if page.description %}
  <meta property="og:description" content="{{ page.description }}">
  {% endif %}
  {% if seo.og_image %}
  <meta property="og:image" content="{{ seo.og_image }}">
  {% endif %}
  {% if seo.fb_app_id %}
  <meta property="fb:app_id" content="{{ seo.fb_app_id }}">
  {% endif %}
  <meta name="twitter:card" content="{{ seo.twitter_card }}">
  <meta name="twitter:title" content="{{ page.title }}">
  {% if seo.twitter_site %}
  <meta name="twitter:site" content="{{ seo.twitter_site }}">
  {% endif %}
</head>
```

---

## Complete Example

### config.toml

```toml
title = "My Site"
description = "A great site"
base_url = "https://example.com"

[sitemap]
enabled = true

[feeds]
enabled = true
limit = 20

[robots]
enabled = true

[og]
default_image = "/images/og-default.png"
type = "website"
twitter_card = "summary_large_image"
twitter_site = "@mysite"
```

### templates/base.html

```jinja
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>{{ page.title }} - {{ site.title }}</title>
  <meta name="description" content="{{ page.description | default(value=site.description) }}">
  {{ og_all_tags | safe }}
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
  {{ jsonld | safe }}
  <link rel="alternate" type="application/rss+xml" href="{{ base_url }}/rss.xml">
</head>
<body>
  {% block content %}{% endblock %}
</body>
</html>
```

## See Also

- [LLMs.txt](/features/llms-txt/) — AI/LLM crawler instructions
- [Multilingual](/features/multilingual/) — Hreflang and canonical tags for i18n
- [Configuration](/start/config/) — Full config reference
