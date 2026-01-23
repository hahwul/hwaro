+++
title = "Front Matter Reference"
description = "Complete reference for all front matter fields in Hwaro content files"
+++


Front matter is metadata at the beginning of content files that defines page properties. Hwaro uses TOML format enclosed in `+++` delimiters.

## Basic Structure

```markdown
+++
title = "Page Title"
date = "2024-01-15"
description = "Page description"
+++

Your Markdown content starts here...
```

## Required Fields

### title

The page title. Used in templates, browser tabs, and meta tags.

```toml
title = "Getting Started with Hwaro"
```

| Type | Required | Default |
|------|----------|---------|
| string | Yes | — |

**Usage in templates:**

```erb
<h1><%= page_title %></h1>
<title><%= page_title %> - <%= site_title %></title>
```

## Optional Fields

### date

Publication date in ISO 8601 format. Used for sorting and display.

```toml
date = "2024-01-15"
date = "2024-01-15T10:30:00Z"
```

| Type | Required | Default |
|------|----------|---------|
| string | No | — |

### description

Page description for SEO and social sharing. Falls back to site description if not set.

```toml
description = "Learn how to install and configure Hwaro"
```

| Type | Required | Default |
|------|----------|---------|
| string | No | Site description |

**Usage in templates:**

```erb
<meta name="description" content="<%= page_description %>">
```

### draft

Mark content as draft. Drafts are excluded from production builds unless `--drafts` flag is used.

```toml
draft = true
```

| Type | Required | Default |
|------|----------|---------|
| bool | No | `false` |

**Building with drafts:**

```bash
hwaro build --drafts
hwaro serve --drafts
```

### layout

Override the default template for this page.

```toml
layout = "landing"
```

| Type | Required | Default |
|------|----------|---------|
| string | No | Auto-detected |

This looks for `templates/landing.ecr` instead of the default `page.ecr` or `section.ecr`.

### weight

Numeric value for custom sorting. Lower numbers appear first.

```toml
weight = 10
```

| Type | Required | Default |
|------|----------|---------|
| int | No | `0` |

Useful for controlling page order in section listings.

### image

Featured image for social sharing (OpenGraph/Twitter Cards).

```toml
image = "/images/featured-post.png"
```

| Type | Required | Default |
|------|----------|---------|
| string | No | `og.default_image` from config |

**Usage in templates:**

```erb
<meta property="og:image" content="<%= base_url %><%= page_image %>">
```

## Taxonomy Fields

### tags

Array of tags for content classification.

```toml
tags = ["tutorial", "beginner", "crystal"]
```

| Type | Required | Default |
|------|----------|---------|
| array | No | `[]` |

Requires `tags` taxonomy in config:

```toml
[[taxonomies]]
name = "tags"
```

### categories

Array of categories for content grouping.

```toml
categories = ["Documentation", "Guides"]
```

| Type | Required | Default |
|------|----------|---------|
| array | No | `[]` |

Requires `categories` taxonomy in config:

```toml
[[taxonomies]]
name = "categories"
```

### Custom Taxonomies

Any taxonomy defined in config can be used as a front matter field:

```toml
[[taxonomies]]
name = "authors"

[[taxonomies]]
name = "series"
```

```toml
+++
title = "My Post"
authors = ["Jane Doe", "John Smith"]
series = ["Building a Blog"]
+++
```

## Section Index Fields

For `_index.md` files (section index pages):

### title

Section title displayed on the index page.

```toml
+++
title = "Blog"
+++
```

### description

Section description for SEO and display.

```toml
+++
title = "Blog"
description = "Latest news, tutorials, and updates"
+++
```

## Complete Example

### Regular Page

```toml
+++
title = "Building REST APIs with Crystal"
date = "2024-01-15T10:30:00Z"
description = "A comprehensive guide to building RESTful APIs using Crystal and Kemal framework"
draft = false
tags = ["crystal", "api", "rest", "kemal", "backend"]
categories = ["Tutorials", "Backend"]
authors = ["Jane Developer"]
image = "/images/posts/rest-api-guide.png"
weight = 10
+++
```

### Section Index

```toml
+++
title = "Tutorials"
description = "Step-by-step guides for learning Hwaro"
+++
```

### Landing Page with Custom Layout

```toml
+++
title = "Welcome"
layout = "landing"
description = "Hwaro - Fast and lightweight static site generator"
+++
```

### Draft Post

```toml
+++
title = "Upcoming Feature Preview"
date = "2024-02-01"
draft = true
tags = ["preview", "upcoming"]
+++
```

## Field Reference Table

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `title` | string | required | Page title |
| `date` | string | — | Publication date (ISO 8601) |
| `description` | string | Site description | Page description for SEO |
| `draft` | bool | `false` | Exclude from production builds |
| `layout` | string | auto | Template override |
| `weight` | int | `0` | Sort order (lower = first) |
| `image` | string | Config default | Featured image for social sharing |
| `tags` | array | `[]` | Tag taxonomy terms |
| `categories` | array | `[]` | Category taxonomy terms |
| `[taxonomy]` | array | `[]` | Any custom taxonomy |

## Best Practices

### Always Include Title

Every page needs a title:

```toml
+++
title = "Clear, Descriptive Title"
+++
```

### Write Good Descriptions

Descriptions appear in search results and social shares:

```toml
description = "Learn how to configure sitemaps, RSS feeds, and meta tags in Hwaro for better SEO"
```

Keep descriptions between 150-160 characters for optimal display.

### Use Dates Consistently

Use ISO 8601 format for dates:

```toml
date = "2024-01-15"
date = "2024-01-15T10:30:00Z"

date = "January 15, 2024"
date = "01/15/2024"
```

### Tag Thoughtfully

Use relevant, consistent tags:

```toml
tags = ["crystal-lang", "web-development", "tutorial"]

tags = ["Crystal", "crystal", "programming", "code", "web", "dev", "tutorial", "guide", "howto"]
```

### Start with Draft

New content should start as draft:

```toml
+++
title = "Work in Progress"
draft = true
+++
```

Remove `draft = true` (or set to `false`) when ready to publish.

## See Also

- [Content Management](/guide/content-management/) — Organizing and writing content
- [Templates](/guide/templates/) — Using front matter values in templates
- [Taxonomies](/guide/taxonomies/) — Content classification
- [Template Variables](/reference/template-variables/) — Accessing front matter in templates