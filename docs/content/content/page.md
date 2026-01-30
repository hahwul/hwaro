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
| `description` | string | site description | Page description for SEO |
| `draft` | bool | `false` | Exclude from production builds |
| `template` | string | auto | Override default template |
| `weight` | int | `0` | Sort order (lower = first) |
| `image` | string | og default | Featured image for social sharing |
| `toc` | bool | `false` | Show table of contents |
| `aliases` | array | `[]` | URL redirects to this page |
| `tags` | array | `[]` | Tag taxonomy terms |
| `categories` | array | `[]` | Category taxonomy terms |

## Examples

### Blog Post

```markdown
+++
title = "Getting Started with Crystal"
date = "2024-01-15"
description = "Learn Crystal programming basics"
tags = ["crystal", "tutorial"]
categories = ["Programming"]
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

| Flat Variable | Object Access | Description |
|---------------|---------------|-------------|
| `page_title` | `page.title` | Page title |
| `page_description` | `page.description` | Page description |
| `page_url` | `page.url` | Page URL path |
| `page_section` | `page.section` | Section name |
| `page_date` | `page.date` | Page date |
| `page_image` | `page.image` | Featured image |
| `content` | — | Rendered HTML content |