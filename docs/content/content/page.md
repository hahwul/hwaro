+++
title = "Page"
toc = true
+++

Pages are Markdown files with TOML front matter that become HTML pages on your site.

## Basic Structure

```markdown
+++
title = "My Page"
date = "2024-01-15"
+++

Your content in **Markdown**.
```

## Front Matter Fields

### Required

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Page title |

### Optional

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `date` | string | — | Publication date (YYYY-MM-DD) |
| `updated` | string | — | Last updated date (YYYY-MM-DD) |
| `description` | string | site description | Page description for SEO |
| `draft` | bool | `false` | Exclude from production builds |
| `template` | string | auto | Override default template |
| `weight` | int | `0` | Sort order (lower = first) |
| `image` | string | og default | Featured image for social sharing |
| `toc` | bool | `false` | Show table of contents |
| `aliases` | array | `[]` | URL redirects to this page |
| `slug` | string | — | Custom URL slug |
| `path` | string | — | Custom URL path |
| `tags` | array | `[]` | Tag taxonomy terms |
| `categories` | array | `[]` | Category taxonomy terms |
| `authors` | array | `[]` | Page authors |
| `in_search_index` | bool | `true` | Include in search index |
| `in_sitemap` | bool | `true` | Include in sitemap |
| `insert_anchor_links` | bool | `false` | Add anchor links to headings |
| `extra` | table | `{}` | Custom metadata fields |

## Examples

### Blog Post

```markdown
+++
title = "Getting Started with Crystal"
date = "2024-01-15"
updated = "2024-02-01"
description = "Learn Crystal programming basics"
tags = ["crystal", "tutorial"]
categories = ["Programming"]
authors = ["Alice Smith", "Bob Jones"]
image = "/images/crystal-guide.png"
+++

Crystal is a fast, compiled language...
```

### Draft Content

```markdown
+++
title = "Work in Progress"
draft = true
+++

This won't appear in production builds.
```

Build with drafts:

```bash
hwaro build --drafts
hwaro serve --drafts
```

### Custom Template

```markdown
+++
title = "Landing Page"
template = "landing"
+++

Hero content here.
```

Uses `templates/landing.html` instead of `page.html`.

### Ordered Pages

Control page order in listings with `weight`:

```markdown
+++
title = "Introduction"
weight = 1
+++
```

```markdown
+++
title = "Getting Started"
weight = 2
+++
```

Lower weight values appear first.

### URL Aliases

Create URL redirects to this page with `aliases`:

```markdown
+++
title = "My Renamed Page"
aliases = ["/old-url/", "/another-old-url/"]
+++

This page is now at a new URL, but old URLs redirect here.
```

### Authors

Specify multiple authors for a page:

```markdown
+++
title = "Collaborative Article"
authors = ["Alice Smith", "Bob Jones", "Carol White"]
+++
```

### Custom Extra Fields

Store arbitrary metadata in the `extra` table:

```markdown
+++
title = "Product Review"

[extra]
rating = 4.5
price = "$29.99"
featured = true
pros = ["Fast", "Reliable", "Affordable"]
cons = ["Limited colors"]
+++
```

### Exclude from Search

Keep a page out of the search index:

```markdown
+++
title = "Terms of Service"
in_search_index = false
+++
```

## Content Summary

Use the `<!-- more -->` marker to define a summary:

```markdown
+++
title = "Long Article"
+++

This introduction will be used as the summary.
It appears in listings and RSS feeds.

<!-- more -->

The full article continues here with more details...
```

The content before `<!-- more -->` becomes `page.summary`.

## Markdown Content

### Headings

```markdown
## Heading 2
### Heading 3
#### Heading 4
```

### Text Formatting

```markdown
**bold** and *italic*
`inline code`
[link text](https://example.com)
```

### Lists

```markdown
- Unordered item
- Another item

1. Ordered item
2. Another item
```

### Code Blocks

````markdown
```javascript
function greet(name) {
  console.log(`Hello, ${name}!`);
}
```
````

### Images

```markdown
![Alt text](/images/photo.jpg)
```

### Tables

```markdown
| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |
```

### Blockquotes

```markdown
> This is a quote.
```

## Raw HTML

Include HTML directly in Markdown:

```markdown
This is Markdown.

<div class="custom">
  <p>This is HTML.</p>
</div>

Back to Markdown.
```

To strip raw HTML, set `markdown.safe = true` in config.

## Template Variables

Page front matter is available in templates via both flat variables and object access:

### Flat Variables

| Variable | Description |
|----------|-------------|
| `page_title` | Page title |
| `page_description` | Page description |
| `page_url` | Page URL path |
| `page_section` | Section name |
| `page_date` | Page date |
| `page_image` | Featured image |
| `page_summary` | Content summary |
| `page_word_count` | Word count |
| `page_reading_time` | Reading time (minutes) |
| `page_permalink` | Absolute URL |
| `page_authors` | Authors array |
| `page_weight` | Sort weight |
| `content` | Rendered HTML content |

### Page Object Properties

| Property | Type | Description |
|----------|------|-------------|
| `page.title` | string | Page title |
| `page.description` | string | Page description |
| `page.url` | string | Relative URL path |
| `page.permalink` | string | Absolute URL with base_url |
| `page.section` | string | Section name |
| `page.date` | string | Publication date |
| `page.updated` | string | Last updated date |
| `page.image` | string | Featured image |
| `page.draft` | bool | Is draft |
| `page.toc` | bool | Show TOC |
| `page.render` | bool | Should render |
| `page.is_index` | bool | Is index page |
| `page.generated` | bool | Is generated |
| `page.in_sitemap` | bool | Include in sitemap |
| `page.in_search_index` | bool | Include in search |
| `page.language` | string | Language code |
| `page.weight` | int | Sort weight |
| `page.word_count` | int | Word count |
| `page.reading_time` | int | Reading time (minutes) |
| `page.summary` | string | Content summary |
| `page.authors` | array | Author names |
| `page.extra` | object | Custom metadata |
| `page.lower` | object | Previous page |
| `page.higher` | object | Next page |
| `page.ancestors` | array | Parent sections |

### Using Extra Fields

```jinja
{% if page.extra.featured %}
<span class="badge">Featured</span>
{% endif %}

<div class="rating">{{ page.extra.rating }} / 5</div>

<ul class="pros">
{% for pro in page.extra.pros %}
  <li>{{ pro }}</li>
{% endfor %}
</ul>
```

### Previous/Next Navigation

```jinja
<nav class="post-nav">
  {% if page.lower %}
  <a href="{{ page.lower.url }}" class="prev">
    ← {{ page.lower.title }}
  </a>
  {% endif %}
  
  {% if page.higher %}
  <a href="{{ page.higher.url }}" class="next">
    {{ page.higher.title }} →
  </a>
  {% endif %}
</nav>
```

### Breadcrumbs

```jinja
<nav class="breadcrumbs">
  <a href="/">Home</a>
  {% for ancestor in page.ancestors %}
  / <a href="{{ ancestor.url }}">{{ ancestor.title }}</a>
  {% endfor %}
  / <span>{{ page.title }}</span>
</nav>
```

### Word Count and Reading Time

```jinja
<div class="meta">
  {{ page.word_count }} words · {{ page.reading_time }} min read
</div>
```

### Authors Display

```jinja
{% if page.authors %}
<div class="authors">
  By: {{ page.authors | join(", ") }}
</div>
{% endif %}
```

## See Also

- [Section Documentation](/content/section/)
- [Template Variables](/templates/variables/)
