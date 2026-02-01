+++
title = "Sections"
weight = 2
toc = true
+++

Sections are directories that group related content. They require an `_index.md` file.

## Creating a Section

```
content/
└── blog/
    ├── _index.md     # Section index → /blog/
    ├── first.md      # Page → /blog/first/
    └── second.md     # Page → /blog/second/
```

## Section Index

Every section needs an `_index.md`:

```markdown
+++
title = "Blog"
description = "Latest articles"
sort_by = "date"
+++

Welcome to my blog.
```

## Front Matter

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| title | string | — | Section title (required) |
| description | string | — | Section description |
| template | string | "section" | Template to use |
| page_template | string | — | Default template for pages |
| sort_by | string | "date" | Sort by: date, weight, title |
| reverse | bool | false | Reverse sort order |
| paginate | int | — | Pages per page |
| paginate_path | string | "page" | Pagination URL pattern |
| transparent | bool | false | Pass pages to parent |
| generate_feeds | bool | false | Generate RSS feed |
| redirect_to | string | — | Redirect URL |
| draft | bool | false | Exclude from production |
| weight | int | 0 | Section sort order |

## Examples

### Blog with Pagination

```toml
+++
title = "Blog"
sort_by = "date"
paginate = 10
paginate_path = "p"
+++
```

Generates: `/blog/`, `/blog/p/2/`, `/blog/p/3/`

### Documentation

```toml
+++
title = "Docs"
page_template = "doc-page"
sort_by = "weight"
+++
```

All pages use `doc-page.html` template and sort by weight.

### Section with Feed

```toml
+++
title = "News"
generate_feeds = true
+++
```

Generates `/news/rss.xml`.

## Nested Sections

Sections can contain other sections:

```
content/
└── docs/
    ├── _index.md           # /docs/
    ├── getting-started/
    │   ├── _index.md       # /docs/getting-started/
    │   └── install.md      # /docs/getting-started/install/
    └── guides/
        ├── _index.md       # /docs/guides/
        └── deploy.md       # /docs/guides/deploy/
```

Access subsections in templates:

```jinja
{% for sub in section.subsections %}
<a href="{{ sub.url }}">{{ sub.title }}</a>
{% endfor %}
```

## Transparent Sections

Use `transparent = true` to merge pages into parent section:

```toml
+++
title = "2024 Posts"
transparent = true
+++
```

Pages appear in the parent's `section.pages` list.

## Section vs Page

| File | Type | URL |
|------|------|-----|
| _index.md | Section index | `/blog/` |
| index.md | Regular page | `/blog/` |

Use `_index.md` when you need to list child pages.
