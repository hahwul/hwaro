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

## Asset Colocation

Just like regular pages, sections can have colocated assets. Place non-markdown files in the same directory as the `_index.md` file.

**Example Structure:**

```text
content/
└── gallery/
    ├── _index.md       <-- The section index
    ├── banner.jpg      <-- Section asset
    └── icon.png        <-- Section asset
```

These assets are copied to the output directory relative to the section.

### Accessing Assets in Templates

You can access the list of section assets in your templates using `section.assets`. This returns an array of relative paths to the files (from the content directory).

```jinja
<!-- In section.html -->
<div class="gallery">
  {% for asset in section.assets %}
    <img src="{{ get_url(path=asset) }}" alt="Section Asset">
  {% endfor %}
</div>
```

## Section vs Page

| File | Type | URL |
|------|------|-----|
| _index.md | Section index | `/blog/` |
| index.md | Regular page | `/blog/` |

Use `_index.md` when you need to list child pages.
