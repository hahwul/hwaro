+++
title = "Writing"
description = "Create content with Markdown and front matter"
+++

Content lives in the `content/` directory. Write Markdown with TOML (`+++`), YAML (`---`), or JSON (`{...}`) front matter. TOML is the default; YAML is widely recommended; JSON is supported for users who prefer it.

## Content Types

| Type | File | URL |
|------|------|-----|
| Page | about.md | /about/ |
| Section | blog/_index.md | /blog/ |
| Section Page | blog/post.md | /blog/post/ |

## Basic Content File

```markdown
+++
title = "My Page"
date = "2024-01-15"
+++

Content in **Markdown**.
```

## Where to Start

Start with **Pages** to learn the basics of content files and front matter. Then read **Sections** to organize content into groups like a blog or docs. From there:

- **Taxonomies** — Classify pages by tags, categories, or custom groups
- **Shortcodes** — Embed reusable components (YouTube, alerts, galleries) inside Markdown
- **Archetypes** — Define templates for `hwaro new` to scaffold content quickly
