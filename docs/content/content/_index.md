+++
title = "Overview"
+++

The `content/` directory contains all your site's content written in Markdown with TOML front matter.

## Content Types

### Pages

Regular content files that become individual pages:

```
content/
├── index.md          # Homepage (/)
├── about.md          # /about/
└── contact.md        # /contact/
```

### Sections

Directories with `_index.md` that group related content:

```
content/
└── blog/
    ├── _index.md     # Section index (/blog/)
    ├── first.md      # /blog/first/
    └── second.md     # /blog/second/
```

## URL Mapping

| File Path | URL |
|-----------|-----|
| `content/index.md` | `/` |
| `content/about.md` | `/about/` |
| `content/blog/_index.md` | `/blog/` |
| `content/blog/post.md` | `/blog/post/` |
| `content/docs/guide/intro.md` | `/docs/guide/intro/` |

## Basic Content File

```markdown
+++
title = "My Page"
date = "2024-01-15"
description = "Page description"
+++

Your content in **Markdown**.
```

## In This Section

- [Section](/content/section/) — Organize content with sections
- [Page](/content/page/) — Page front matter and content
- [Shortcodes](/content/shortcodes/) — Reusable content components
- [Table of Contents](/content/table-of-contents/) — Auto-generated TOC
- [Syntax Highlighting](/content/syntax-highlighting/) — Code block highlighting
- [Taxonomies](/content/taxonomies/) — Tags, categories, and more
- [Search](/content/search/) — Client-side search