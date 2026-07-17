+++
title = "Taxonomies"
description = "Organize content with tags, categories, and custom groups"
weight = 3
toc = true
+++

Taxonomies organize content into groups like tags, categories, or authors.

## Configuration

Define taxonomies in `config.toml`:

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate_by = 10

[[taxonomies]]
name = "categories"
feed = true

[[taxonomies]]
name = "authors"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `name` | string | — | Taxonomy name (used in front matter) |
| `feed` | bool | false | Generate RSS feed for each term |
| `sitemap` | bool | true | Include taxonomy pages in sitemap |
| `paginate_by` | int | — | Items per page on term pages |
| `sort_by` | string | "date" | Order of pages within a term: `"date"`, `"title"`, or `"weight"` (see [Sorting](#sorting)) |
| `reverse` | bool | false | Flip whichever order `sort_by` produced |
| `terms_sort_by` | string | "name" | Order of the terms list: `"name"` or `"count"` (see [Sorting](#sorting)) |

## Sorting

`sort_by` controls the order of pages within each term — on the written
term pages, in `term.pages` from `get_taxonomy()`, and in per-term
pagination. The semantics match section sorting exactly:

- `"date"` (default) — newest first; `reverse = true` gives oldest first.
- `"title"` — alphabetical ascending; `reverse = true` descends.
- `"weight"` — lowest weight first; `reverse = true` descends.

An invalid `sort_by` value logs a warning and keeps the `"date"` default.

`terms_sort_by` controls the order of the terms list — on the taxonomy
index page and in `get_taxonomy().items`:

- `"name"` (default) — alphabetical ascending.
- `"count"` — page count descending, name-ascending tiebreak. On a
  multilingual site, each language's index uses that language's own page
  counts.

**Term feeds are exempt.** With `feed = true`, each term's RSS feed stays
reverse-chronological regardless of `sort_by` — RSS consumers assume
newest-first entries.

```toml
[[taxonomies]]
name = "tags"
sort_by = "title"
terms_sort_by = "count"
```

## Using Taxonomies

Assign terms in front matter:

```markdown
+++
title = "My Post"
tags = ["crystal", "tutorial"]
categories = ["Programming"]
authors = ["Alice"]
+++
```

A Zola-style `[taxonomies]` table works too (both spellings are equivalent;
an explicit top-level key wins if both are present):

```markdown
+++
title = "My Post"
[taxonomies]
tags = ["crystal", "tutorial"]
tech = ["crystal", "security"]
+++
```

In templates, a page's own terms are available as `page.taxonomies.<name>`
(e.g. `{% for t in page.taxonomies.tech %}`) — also on the page objects
inside `section.pages`, `site.pages`, and term page lists.

## Generated URLs

For a taxonomy named `tags` with term `crystal`:

| URL | Content |
|-----|---------|
| `/tags/` | List of all tags |
| `/tags/crystal/` | Pages tagged "crystal" |

With `paginate_by` set, term pages paginate at `/tags/crystal/page/2/`, `/tags/crystal/page/3/`, … (page 1 stays at `/tags/crystal/`). The pager object is described in [Data Model › Paginator](/templates/data-model/#paginator).

## Templates

Both templates receive a ready-made listing as `{{ content }}` — the term list in `taxonomy.html`, the page list in `taxonomy_term.html`. For custom markup, use [`get_taxonomy()`](#get-taxonomy-function) instead of `content`.

### Taxonomy Index

`templates/taxonomy.html` — List of all terms:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ page.title }}</h1>
{{ content }}
{% endblock %}
```

Custom term list:

```jinja
{% set tax = get_taxonomy(kind=taxonomy_name) %}
<ul>
{% for term in tax.items %}
  <li>
    <a href="{{ get_taxonomy_url(kind=taxonomy_name, term=term.name) }}">
      {{ term.name }} ({{ term.count }})
    </a>
  </li>
{% endfor %}
</ul>
```

### Taxonomy Term

`templates/taxonomy_term.html` — Pages for a specific term:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ taxonomy_name }}: {{ taxonomy_term }}</h1>
{{ content }}
{% endblock %}
```

Custom page list — look up the current term's pages via `get_taxonomy()`:

```jinja
{% set tax = get_taxonomy(kind=taxonomy_name) %}
{% for term in tax.items if term.name == taxonomy_term %}
<ul>
{% for p in term.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>
{% endfor %}
```

## Template Variables

Available in both `taxonomy.html` and `taxonomy_term.html`:

| Variable | Type | Description |
|----------|------|-------------|
| taxonomy_name | String | Taxonomy name ("tags") |
| taxonomy_term | String | Current term name (empty on the index page) |
| content | String | Pre-rendered listing HTML (terms or pages) |

### Term Object

| Property | Type | Description |
|----------|------|-------------|
| name | String | Term name |
| slug | String | URL-safe name |
| pages | Array<Page> | Pages with this term |
| count | Int | Number of pages |

## get_taxonomy() Function

Access taxonomy data anywhere:

```jinja
{% set tags = get_taxonomy(kind="tags") %}
{% if tags %}
<div class="tag-cloud">
{% for term in tags.items %}
  <a href="/tags/{{ term.slug }}/">{{ term.name }}</a>
{% endfor %}
</div>
{% endif %}
```

## get_taxonomy_url() Function

Generate taxonomy term URL:

```jinja
<a href="{{ get_taxonomy_url(kind='tags', term='crystal') }}">
  Crystal articles
</a>
```

## Common Patterns

### Tag Cloud

```jinja
{% set tags = get_taxonomy(kind="tags") %}
<div class="tags">
{% for term in tags.items %}
  <a href="/tags/{{ term.slug }}/" 
     class="tag count-{{ term.count }}">
    {{ term.name }}
  </a>
{% endfor %}
</div>
```

### Display Page Tags

```jinja
{% if page.tags %}
<div class="post-tags">
{% for tag in page.tags %}
  <a href="/tags/{{ tag | slugify }}/">{{ tag }}</a>
{% endfor %}
</div>
{% endif %}
```

### Category Navigation

```jinja
{% set categories = get_taxonomy(kind="categories") %}
<nav class="categories">
{% for cat in categories.items %}
  <a href="/categories/{{ cat.slug }}/">
    {{ cat.name }} ({{ cat.count }})
  </a>
{% endfor %}
</nav>
```

## See Also

- [Sections](/writing/sections/) — Group content with directories
- [Configuration](/start/config/) — Taxonomy config reference
- [Data Model](/templates/data-model/) — Taxonomy variables in templates
