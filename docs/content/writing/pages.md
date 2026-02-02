+++
title = "Pages"
weight = 2
toc = true
+++

Pages are Markdown files that become HTML pages on your site.

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

## URL Mapping

| File | URL |
|------|-----|
| content/index.md | `/` |
| content/about.md | `/about/` |
| content/blog/post.md | `/blog/post/` |

## See Also

- [Sections](/writing/sections/) — Group related pages
- [Data Model](/templates/data-model/) — Page properties in templates
