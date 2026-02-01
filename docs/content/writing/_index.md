+++
title = "Writing"
description = "Create content with Markdown and front matter"
+++

Content lives in the `content/` directory. Write Markdown with TOML front matter.

## Content Types

| Type | File | URL |
|------|------|-----|
| Page | `about.md` | `/about/` |
| Section | `blog/_index.md` | `/blog/` |
| Section Page | `blog/post.md` | `/blog/post/` |

## Basic Content File

```markdown
+++
title = "My Page"
date = "2024-01-15"
+++

Content in **Markdown**.
```

## Documentation

1. [Pages](/writing/pages/) — Create individual pages
2. [Sections](/writing/sections/) — Group related content
3. [Taxonomies](/writing/taxonomies/) — Tags, categories, and custom terms
4. [Shortcodes](/writing/shortcodes/) — Reusable content components