+++
title = "SEO"
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
limit = 20
```

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

Language feeds share the same `sections`, `limit`, and `truncate` settings from `[feeds]` config. RSS language feeds include a `<language>` tag, and Atom feeds include an `xml:lang` attribute. The feed title includes the language name (e.g., `"My Site (한국어)"`).

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

### Output

```
User-agent: *
Allow: /
Sitemap: https://example.com/sitemap.xml
```

---

## LLMs.txt

Generate instruction files for AI/LLM crawlers following the [llms.txt standard](https://llmstxt.org/).

### Configuration

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
| instructions | string | "" | Instructions for LLM crawlers |
| full_enabled | bool | false | Generate full content version |
| full_filename | string | "llms-full.txt" | Full version filename |

### Output

- `/llms.txt` — Instructions text only
- `/llms-full.txt` — Full site content with metadata (title, URL, source path per page)

The full version includes all rendered pages sorted by URL, separated by `---` delimiters.

See [LLMs.txt](/features/llms-txt/) for detailed documentation.

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
| type | OpenGraph type (website, article) |
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

Hwaro generates [JSON-LD](https://json-ld.org/) structured data for search engines.

### Template Variables

| Variable | Description |
|----------|-------------|
| jsonld | Both Article and BreadcrumbList JSON-LD |
| jsonld_article | Article JSON-LD only |
| jsonld_breadcrumb | BreadcrumbList JSON-LD only |

### Template Usage

```jinja
<head>
  {{ jsonld | safe }}
</head>
```

Or include specific types:

```jinja
<head>
  {{ jsonld_article | safe }}
  {{ jsonld_breadcrumb | safe }}
</head>
```

### Article Output

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "My Article",
  "url": "https://example.com/blog/my-article/",
  "datePublished": "2024-01-15T00:00:00+00:00",
  "dateModified": "2024-02-01T00:00:00+00:00",
  "description": "Article description",
  "author": {
    "@type": "Person",
    "name": "Author Name"
  }
}
</script>
```

### BreadcrumbList Output

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    {"@type": "ListItem", "position": 1, "name": "My Site", "item": "https://example.com/"},
    {"@type": "ListItem", "position": 2, "name": "Blog", "item": "https://example.com/blog/"},
    {"@type": "ListItem", "position": 3, "name": "My Article"}
  ]
}
</script>
```

### Fields Included

The Article JSON-LD includes the following fields when available:

| Field | Source |
|-------|--------|
| headline | `page.title` |
| url | `page.permalink` or computed from `base_url` |
| datePublished | `page.date` |
| dateModified | `page.updated` |
| description | `page.description` |
| image | `page.image` |
| author | First entry from `page.authors` |

---

## Template Variables

| Variable | Description |
|----------|-------------|
| og_tags | OpenGraph meta tags |
| twitter_tags | Twitter Card meta tags |
| og_all_tags | Both OG and Twitter tags |
| jsonld | Article + BreadcrumbList JSON-LD |
| jsonld_article | Article JSON-LD only |
| jsonld_breadcrumb | BreadcrumbList JSON-LD only |
| page_description | Page description (fallback: site) |
| page_image | Page image (fallback: og.default_image) |

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
