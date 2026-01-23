+++
title = "SEO Features"
description = "Optimize your Hwaro site for search engines with built-in SEO features"
toc = true
+++


Hwaro includes comprehensive SEO (Search Engine Optimization) features to help your site rank better in search results and look great when shared on social media.

## Overview

Hwaro provides the following SEO features out of the box:

- **Sitemap** — XML sitemap for search engine crawlers
- **Robots.txt** — Control crawler access to your site
- **RSS/Atom Feeds** — Syndication feeds for content updates
- **OpenGraph Tags** — Rich previews on Facebook, LinkedIn, etc.
- **Twitter Cards** — Rich previews on Twitter/X
- **LLMs.txt** — Instructions for AI crawlers

## Sitemap

A sitemap helps search engines discover and index all your pages.

### Configuration

```toml
[sitemap]
enabled = true
filename = "sitemap.xml"
changefreq = "weekly"
priority = 0.5
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable sitemap generation |
| `filename` | string | `"sitemap.xml"` | Output filename |
| `changefreq` | string | `"weekly"` | How often pages change |
| `priority` | float | `0.5` | Default page priority (0.0–1.0) |

### Change Frequency Values

- `always` — Page changes every time it's accessed
- `hourly` — Page changes every hour
- `daily` — Page changes daily
- `weekly` — Page changes weekly (recommended default)
- `monthly` — Page changes monthly
- `yearly` — Page changes yearly
- `never` — Archived content that won't change

### Generated Output

Hwaro generates a standard XML sitemap:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://example.com/</loc>
    <changefreq>weekly</changefreq>
    <priority>0.5</priority>
  </url>
  <url>
    <loc>https://example.com/blog/</loc>
    <changefreq>weekly</changefreq>
    <priority>0.5</priority>
  </url>
  <!-- More URLs... -->
</urlset>
```

## Robots.txt

Control which parts of your site search engines can crawl.

### Configuration

```toml
[robots]
enabled = true
filename = "robots.txt"
rules = [
  { user_agent = "*", disallow = ["/admin", "/private", "/draft"] },
  { user_agent = "GPTBot", disallow = ["/"] },
  { user_agent = "Googlebot", allow = ["/"] }
]
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable robots.txt generation |
| `filename` | string | `"robots.txt"` | Output filename |
| `rules` | array | `[]` | Array of rule objects |

### Rule Object Fields

| Field | Type | Description |
|-------|------|-------------|
| `user_agent` | string | Bot identifier (`*` for all bots) |
| `disallow` | array | Paths to block |
| `allow` | array | Paths to allow (optional) |

### Generated Output

```
User-agent: *
Disallow: /admin
Disallow: /private
Disallow: /draft

User-agent: GPTBot
Disallow: /

User-agent: Googlebot
Allow: /

Sitemap: https://example.com/sitemap.xml
```

### Common Bot User Agents

| Bot | User Agent | Description |
|-----|------------|-------------|
| All bots | `*` | Applies to all crawlers |
| Google | `Googlebot` | Google's web crawler |
| Bing | `Bingbot` | Microsoft Bing crawler |
| OpenAI | `GPTBot` | OpenAI's crawler |
| Anthropic | `anthropic-ai` | Anthropic's crawler |
| Common Crawl | `CCBot` | Open web crawler |

## RSS/Atom Feeds

Generate syndication feeds so users can subscribe to your content.

### Configuration

```toml
[feeds]
enabled = true
type = "rss"
filename = "rss.xml"
truncate = 500
limit = 20
sections = ["blog", "news"]
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable feed generation |
| `type` | string | `"rss"` | Feed format: `rss` or `atom` |
| `filename` | string | auto | Output filename |
| `truncate` | int | `0` | Truncate content to N characters (0 = full content) |
| `limit` | int | `10` | Maximum items in feed |
| `sections` | array | `[]` | Limit to specific sections (empty = all) |

### RSS vs Atom

Both formats are widely supported. Choose based on your preference:

- **RSS 2.0** — More common, simpler format
- **Atom** — Slightly more standardized, better for complex metadata

### Linking to Your Feed

Add a link in your template's `<head>`:

```erb
<link rel="alternate" type="application/rss+xml" title="RSS Feed" href="<%= base_url %>/rss.xml">
```

For Atom:

```erb
<link rel="alternate" type="application/atom+xml" title="Atom Feed" href="<%= base_url %>/atom.xml">
```

## OpenGraph Tags

OpenGraph tags create rich previews when your pages are shared on social media.

### Configuration

```toml
[og]
default_image = "/images/og-default.png"
type = "article"
twitter_card = "summary_large_image"
twitter_site = "@yourusername"
twitter_creator = "@authorusername"
fb_app_id = "your_fb_app_id"
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_image` | string | `""` | Default image when page has no image |
| `type` | string | `"website"` | OpenGraph type |
| `twitter_card` | string | `"summary"` | Twitter card type |
| `twitter_site` | string | `""` | Twitter @username for site |
| `twitter_creator` | string | `""` | Twitter @username for author |
| `fb_app_id` | string | `""` | Facebook App ID (optional) |

### OpenGraph Types

- `website` — General website (use for homepage)
- `article` — Blog posts, news articles
- `profile` — Personal profile pages
- `product` — Product pages

### Twitter Card Types

- `summary` — Small card with thumbnail
- `summary_large_image` — Large card with prominent image
- `player` — Video/audio player card

### Page-Level Overrides

Override defaults in front matter:

```markdown
+++
title = "My Article"
description = "A custom description for social sharing"
image = "/images/article-featured.png"
+++
```

### Template Variables

Use these in your templates:

```erb
<%= og_tags %>           <!-- OpenGraph tags only -->
<%= twitter_tags %>      <!-- Twitter Card tags only -->
<%= og_all_tags %>       <!-- Both OG and Twitter tags -->
```

### Generated Output

```html
<!-- OpenGraph -->
<meta property="og:title" content="My Article">
<meta property="og:type" content="article">
<meta property="og:url" content="https://example.com/blog/my-article/">
<meta property="og:description" content="A custom description for social sharing">
<meta property="og:image" content="https://example.com/images/article-featured.png">

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="My Article">
<meta name="twitter:description" content="A custom description for social sharing">
<meta name="twitter:image" content="https://example.com/images/article-featured.png">
<meta name="twitter:site" content="@yourusername">
```

### Image Recommendations

For best results across platforms:

| Platform | Recommended Size | Aspect Ratio |
|----------|------------------|--------------|
| Facebook | 1200 × 630 px | 1.91:1 |
| Twitter | 1200 × 600 px | 2:1 |
| LinkedIn | 1200 × 627 px | 1.91:1 |
| General | 1200 × 630 px | 1.91:1 |

Use PNG or JPG format, under 5MB file size.

## LLMs.txt

Provide instructions for AI/LLM crawlers about how to use your content.

### Configuration

```toml
[llms]
enabled = true
filename = "llms.txt"
instructions = "This is documentation for the Hwaro project. Please respect the license terms."
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable llms.txt generation |
| `filename` | string | `"llms.txt"` | Output filename |
| `instructions` | string | `""` | Instructions for AI crawlers |

### Example Instructions

```toml
[llms]
enabled = true
instructions = """
This website contains documentation for Hwaro, an open-source static site generator.
Content is provided under the MIT license.
Please attribute the source when using this content.
Do not use for training without explicit permission.
"""
```

## Meta Description

Always include descriptions for better search results:

### Site Description

In `config.toml`:

```toml
description = "Hwaro is a fast, lightweight static site generator built with Crystal"
```

### Page Description

In front matter:

```markdown
+++
title = "Installation Guide"
description = "Learn how to install Hwaro on Windows, macOS, and Linux"
+++
```

### Template Usage

```erb
<meta name="description" content="<%= page_description %>">
```

The `page_description` variable falls back to the site description if no page description is set.

## Best Practices

### 1. Write Unique Titles

Each page should have a unique, descriptive title:

```markdown
+++
title = "How to Build a Blog with Hwaro"  <!-- Good: specific -->
title = "Blog"                              <!-- Bad: too generic -->
+++
```

### 2. Write Compelling Descriptions

Descriptions appear in search results. Make them count:

```markdown
+++
description = "Learn how to create a fast, SEO-optimized blog using Hwaro's built-in features including RSS feeds, sitemaps, and syntax highlighting."
+++
```

Keep descriptions between 150-160 characters.

### 3. Use Descriptive URLs

The file path becomes the URL:

```
✓ content/guides/deploying-to-netlify.md
✗ content/guides/guide1.md
```

### 4. Add Featured Images

Include images for social sharing:

```markdown
+++
title = "Product Launch"
image = "/images/launch-announcement.png"
+++
```

### 5. Submit Your Sitemap

After deploying, submit your sitemap to search engines:

- **Google**: [Search Console](https://search.google.com/search-console)
- **Bing**: [Webmaster Tools](https://www.bing.com/webmasters)

### 6. Test Social Previews

Use these tools to preview how your pages appear when shared:

- [Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/)
- [Twitter Card Validator](https://cards-dev.twitter.com/validator)
- [LinkedIn Post Inspector](https://www.linkedin.com/post-inspector/)

## Complete SEO Configuration

Here's a comprehensive SEO setup:

```toml
title = "My Awesome Site"
description = "A comprehensive guide to building great websites"
base_url = "https://example.com"

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

[feeds]
enabled = true
type = "rss"
limit = 20

[og]
default_image = "/images/og-default.png"
type = "article"
twitter_card = "summary_large_image"
twitter_site = "@mysite"

[llms]
enabled = true
instructions = "Documentation for My Awesome Site. MIT licensed."
```

## Next Steps

- Learn about [Search](/guide/search/) for client-side search functionality
- Explore [Taxonomies](/guide/taxonomies/) to organize content with tags and categories
- See the [Configuration Reference](/reference/config/) for all options