+++
title = "Section"
toc = true
+++

Sections are directories that group related content. They require an `_index.md` file.

## Creating a Section

```
content/
└── blog/
    ├── _index.md     # Required: section index
    ├── first.md      # /blog/first/
    └── second.md     # /blog/second/
```

## Section Index

The `_index.md` defines the section:

```markdown
+++
title = "Blog"
description = "Latest articles"
+++

Welcome to my blog.
```

This content appears at `/blog/`.

## Front Matter Fields

### Required

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Section title |

### Optional

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `description` | string | — | Section description for SEO |
| `template` | string | "section" | Override section template |
| `page_template` | string | — | Default template for pages in this section |
| `sort_by` | string | "date" | Sort pages by: date, weight, title |
| `reverse` | bool | `false` | Reverse sort order |
| `paginate` | int | — | Pages per pagination page |
| `paginate_path` | string | "page" | Path pattern for pagination URLs |
| `pagination_enabled` | bool | config | Enable/disable pagination |
| `transparent` | bool | `false` | Pass pages to parent section |
| `generate_feeds` | bool | `false` | Generate RSS/Atom feed |
| `redirect_to` | string | — | Redirect to another URL |
| `insert_anchor_links` | bool | `false` | Add anchor links to headings |
| `draft` | bool | `false` | Exclude from production builds |
| `weight` | int | `0` | Section sort order |

### Examples

#### Basic Section

```toml
+++
title = "Blog"
description = "Latest articles and tutorials"
sort_by = "date"
+++
```

#### Paginated Section

```toml
+++
title = "Articles"
paginate = 10
paginate_path = "p"
sort_by = "date"
reverse = false
+++
```

This generates:
- `/articles/` (page 1)
- `/articles/p/2/` (page 2)
- `/articles/p/3/` (page 3)

#### Section with Custom Page Template

```toml
+++
title = "Documentation"
page_template = "doc-page"
sort_by = "weight"
insert_anchor_links = true
+++
```

All pages in this section will use `templates/doc-page.html` by default.

#### Section with Feed

```toml
+++
title = "News"
generate_feeds = true
sort_by = "date"
+++
```

Generates `/news/rss.xml` with this section's pages.

#### Redirect Section

```toml
+++
title = "Old Section"
redirect_to = "/new-location/"
+++
```

Visitors to this section are redirected to the new URL.

## Nested Sections

Sections can be nested:

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

### Accessing Subsections

Use `section.subsections` to access child sections:

```jinja
{% if section.subsections %}
<h2>Categories</h2>
<ul>
{% for sub in section.subsections %}
  <li>
    <a href="{{ sub.url }}">{{ sub.title }}</a>
    <span>({{ sub.pages_count }} articles)</span>
    {% if sub.description %}
    <p>{{ sub.description }}</p>
    {% endif %}
  </li>
{% endfor %}
</ul>
{% endif %}
```

## Section Assets

Static files in the section directory (not `.md` files) are collected as assets:

```
content/
└── projects/
    ├── _index.md
    ├── diagram.svg
    ├── data.json
    └── project-1.md
```

Access in templates:

```jinja
{% if section.assets %}
<h3>Downloads</h3>
<ul>
{% for asset in section.assets %}
  <li><a href="/projects/{{ asset }}">{{ asset }}</a></li>
{% endfor %}
</ul>
{% endif %}
```

## Section Template

Sections use `section.html` template by default.

### Available Variables

| Flat Variable | Object Access | Description |
|---------------|---------------|-------------|
| `section_title` | `section.title` | Section title |
| `section_description` | `section.description` | Section description |
| `section_list` | `section.list` | HTML list of pages |
| — | `section.pages` | Array of page objects |
| — | `section.pages_count` | Number of pages |
| — | `section.subsections` | Child sections |
| — | `section.assets` | Static files in section |
| — | `section.page_template` | Default page template |
| — | `section.paginate_path` | Pagination URL pattern |
| — | `section.redirect_to` | Redirect URL |
| `content` | — | Section index content |
| `pagination` | — | Pagination navigation HTML |

### Simple Example (using section.list)

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ section.title }}</h1>
{{ content }}

<h2>Pages</h2>
<ul>{{ section.list }}</ul>

{{ pagination }}
{% endblock %}
```

### Advanced Example (using section.pages)

For more control over section page listing, iterate over `section.pages`:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ section.title }}</h1>
{% if section.description %}
<p class="lead">{{ section.description }}</p>
{% endif %}

{{ content }}

<h2>Articles ({{ section.pages_count }})</h2>
<ul class="article-list">
{% for p in section.pages %}
  <li class="article">
    <a href="{{ p.url }}">{{ p.title }}</a>
    {% if p.date %}<time>{{ p.date }}</time>{% endif %}
    {% if p.description %}<p>{{ p.description }}</p>{% endif %}
    {% if p.reading_time %}
    <span class="meta">{{ p.reading_time }} min read</span>
    {% endif %}
  </li>
{% endfor %}
</ul>

{{ pagination }}
{% endblock %}
```

### Page Properties in section.pages

Each page in `section.pages` has these properties:

| Property | Type | Description |
|----------|------|-------------|
| `title` | string | Page title |
| `description` | string | Page description |
| `url` | string | Page URL |
| `date` | string | Publication date |
| `image` | string | Featured image |
| `draft` | bool | Is draft |
| `toc` | bool | Show TOC |
| `render` | bool | Should render |
| `is_index` | bool | Is index page |
| `generated` | bool | Is generated |
| `in_sitemap` | bool | In sitemap |
| `language` | string | Language code |

## Transparent Sections

Use `transparent = true` to pass pages up to the parent section:

```toml
+++
title = "2024 Posts"
transparent = true
+++
```

Pages in this section will appear in the parent section's page list.

## Section vs Page

| File | Type | URL |
|------|------|-----|
| `_index.md` | Section index | `/blog/` |
| `index.md` | Regular page | `/blog/` |
| `post.md` | Page in section | `/blog/post/` |

Use `_index.md` when you need a listing of child pages.

## Template Functions

### get_section()

Retrieve any section's data in templates:

```jinja
{% set blog = get_section(path="blog") %}
{% if blog %}
<h2>Latest from {{ blog.title }}</h2>
<ul>
{% for page in blog.pages %}
  <li><a href="{{ page.url }}">{{ page.title }}</a></li>
{% endfor %}
</ul>
{% endif %}
```

## See Also

- [Page Documentation](/content/page/)
- [Pagination](/templates/pagination/)
- [Template Variables](/templates/variables/)
