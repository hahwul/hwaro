+++
title = "Pages"
description = "Create pages from Markdown with front matter metadata"
weight = 1
toc = true
+++

Pages are Markdown files that become HTML pages on your site. This page covers **how to write content** — front matter fields, Markdown syntax, and file organization. For how these fields are accessed in templates, see the [Data Model](/templates/data-model/#page).

## Basic Structure

```markdown
+++
title = "My Page"
date = "2024-01-15"
+++

Your content in **Markdown**.
```

The `+++` block is TOML front matter. Content below becomes HTML.

## Front Matter

### Required

| Field | Type | Description |
|-------|------|-------------|
| title | string | Page title |

### Common Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| date | string | — | Publication date (YYYY-MM-DD) |
| description | string | — | SEO description |
| draft | bool | false | Exclude from production builds |
| template | string | "page" | Template to use |
| weight | int | 0 | Sort order (lower = first) |
| image | string | — | Featured image for social sharing |
| tags | array | [] | Tag taxonomy terms |
| categories | array | [] | Category taxonomy terms |

### All Fields

| Field | Type | Description |
|-------|------|-------------|
| updated | string | Last updated date |
| slug | string | Custom URL slug |
| path | string | Custom URL path |
| aliases | array | Redirect URLs to this page |
| authors | array | Author names |
| toc | bool | Show table of contents |
| in_search_index | bool | Include in search |
| in_sitemap | bool | Include in sitemap |
| insert_anchor_links | bool | Add heading anchors |
| redirect_to | string | Redirect page to this URL |
| render | bool | Render page to output (default: true) |
| expires | date | Auto-exclude after this date |
| series | string | Series name for grouping |
| series_weight | int | Sort order within series |
| extra | table | Custom metadata |

## Examples

### Blog Post

```markdown
+++
title = "Getting Started with Crystal"
date = "2024-01-15"
description = "Learn Crystal programming basics"
tags = ["crystal", "tutorial"]
authors = ["Alice Smith"]
image = "/images/crystal-guide.png"
+++

Crystal is a fast, compiled language...
```

### Draft

```markdown
+++
title = "Work in Progress"
draft = true
+++

Not visible in production.
```

Build with drafts: `hwaro build --drafts`

### Expiring Content

```markdown
+++
title = "Limited Time Offer"
expires = 2025-12-31
+++

Automatically excluded from builds after the expiry date.
```

Build with expired content: `hwaro build --include-expired`

Pages expiring within 7 days generate a build warning.

### Future-Dated Content

Pages with a `date` in the future are automatically excluded from builds. This is useful for scheduling content.

```markdown
+++
title = "Coming Soon"
date = 2099-01-01
+++

Published only after the date arrives.
```

Build with future content: `hwaro build --include-future`

### Series Post

```markdown
+++
title = "Part 1: Introduction"
series = "Crystal Tutorial"
series_weight = 1
+++

First part of the series.
```

In templates, access `page.series`, `page.series_index`, and `page.series_pages`.

### Custom Template

```markdown
+++
title = "Landing Page"
template = "landing"
+++

Uses `templates/landing.html` instead of `page.html`.
```

### Weighted Order

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

Lower weight appears first.

### URL Aliases

```markdown
+++
title = "New Page"
aliases = ["/old-url/", "/another-old-url/"]
+++

Redirects from old URLs to this page.
```

### Custom Metadata

```markdown
+++
title = "Product Review"

[extra]
rating = 4.5
featured = true
pros = ["Fast", "Reliable"]
+++
```

Access in templates: `{{ page.extra.rating }}`

## Full Front Matter Reference

All available fields in one block. Copy and remove what you don't need.

```toml
+++
title = "Page Title"
date = "2024-01-15"
updated = "2024-02-01"
description = "SEO description"
draft = false
template = "page"
weight = 0
slug = "custom-slug"
path = "custom/path"
aliases = ["/old-url/"]
image = "/images/cover.png"
tags = ["tag1", "tag2"]
categories = ["category1"]
authors = ["Author Name"]
toc = true
in_search_index = true
in_sitemap = true
insert_anchor_links = true
render = true
redirect_to = ""
expires = 2025-12-31
series = "Series Name"
series_weight = 1

[extra]
custom_field = "value"
+++
```

## Content Summary

Use `<!-- more -->` to define a summary:

```markdown
+++
title = "Long Article"
+++

This is the summary shown in listings.

<!-- more -->

The full article continues here...
```

## Markdown Syntax

### Text

```markdown
**bold** and *italic*
`inline code`
[link](https://example.com)
![image](/img.jpg)
```

### Lists

```markdown
- Unordered
- Items

1. Ordered
2. Items
```

### Code Blocks

````markdown
```javascript
console.log("Hello");
```
````

### Tables

```markdown
| Header | Header |
|--------|--------|
| Cell   | Cell   |
```

Table cells support inline Markdown: **bold**, *italic*, `code spans`, [links](url), ![images](url), and ~~strikethrough~~.

```markdown
| Feature        | Example                          |
|----------------|----------------------------------|
| Bold           | **important**                    |
| Italic         | *emphasis*                       |
| Code           | `config.toml`                    |
| Link           | [Hwaro](https://example.com)     |
| Image          | ![logo](/img/logo.png)           |
| Strikethrough  | ~~deprecated~~                   |
```

### Internal Links

Use `@/` to link to other content pages by their source path. Hwaro resolves these to the correct output URL at build time.

```markdown
[Read the post](@/blog/my-post.md)
[About section](@/about/_index.md)
[With anchor](@/blog/my-post.md#introduction)
```

This is useful because you don't need to know the final URL — Hwaro calculates it from the content path. If the target page doesn't exist, the link is left unchanged and a warning is logged during build.

| Syntax | Resolved URL |
|--------|-------------|
| `@/blog/post.md` | `/blog/post/` |
| `@/blog/_index.md` | `/blog/` |
| `@/blog/post.md#section` | `/blog/post/#section` |

### Blockquotes

```markdown
> Quote text
```

## Asset Colocation

You can keep related assets (images, PDFs, etc.) in the same directory as your content file. This is known as a **Page Bundle**.

To use this feature, rename your markdown file to `index.md` (for regular pages) or `_index.md` (for section pages) and place it in a directory named after your page.

**Example Structure:**

```text
content/
└── blog/
    ├── my-trip/
    │   ├── index.md        <-- The page content
    │   ├── photo.jpg       <-- Asset
    │   └── data.json       <-- Asset
    └── _index.md
```

Hwaro will copy all non-markdown files from the page bundle directory to the output directory, maintaining the relative path.

In your markdown, you can link to these assets using relative paths:

```markdown
![My Trip Photo](photo.jpg)

[Download Data](data.json)
```

### Accessing Assets in Templates

You can access the list of colocated assets in your templates using `page.assets`. This returns an array of relative paths to the files.

```jinja
{% for asset in page.assets %}
  {% if asset is matching("[.](jpg|png)$") %}
    <img src="{{ get_url(path=asset) }}" alt="Gallery Image">
  {% endif %}
{% endfor %}
```

## URL Mapping

| File | URL |
|------|-----|
| content/index.md | `/` |
| content/about.md | `/about/` |
| content/blog/post.md | `/blog/post/` |

## See Also

- [Sections](/writing/sections/) — Group related pages
- [Data Model](/templates/data-model/) — Page properties in templates
