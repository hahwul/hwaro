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
```

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

### Template Links

```jinja
<link rel="alternate" type="application/rss+xml" 
      href="{{ base_url }}/rss.xml" 
      title="{{ site.title }}">
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

## Template Variables

| Variable | Description |
|----------|-------------|
| og_tags | OpenGraph meta tags |
| twitter_tags | Twitter Card meta tags |
| og_all_tags | Both OG and Twitter tags |
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
  <link rel="alternate" type="application/rss+xml" href="{{ base_url }}/rss.xml">
</head>
<body>
  {% block content %}{% endblock %}
</body>
</html>
```
