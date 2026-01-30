+++
title = "Overview"
+++

The `content/` directory contains all your site's content written in Markdown with TOML front matter.

New to Hwaro? Start with the end-to-end walkthrough: [Guide](/guide/).

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
