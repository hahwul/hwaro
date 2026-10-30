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
| `sort_by` | string | "date" | Order of pages within a term: `"date"`, `"published"`, `"title"`, or `"weight"` (see [Sorting](#sorting)) |
| `reverse` | bool | false | Flip whichever order `sort_by` produced |
| `terms_sort_by` | string | "name" | Order of the terms list: `"name"` or `"count"` (see [Sorting](#sorting)) |

## Sorting

`sort_by` controls the order of pages within each term: on the written
term pages, in `term.pages` from `get_taxonomy()`, and in per-term
pagination. The semantics match section sorting exactly:

- `"date"` (default): newest first; `reverse = true` gives oldest first.
- `"published"` — like `"date"`, but on the publish `date` alone (`updated` is ignored).
- `"title"` — ascending by title, compared byte by byte (uppercase before lowercase); `reverse = true` descends.
- `"weight"` — lowest weight first; `reverse = true` descends.

An invalid `sort_by` value logs a warning and keeps the `"date"` default.

`terms_sort_by` controls the order of the terms list, on the taxonomy
index page and in `get_taxonomy().items`:

- `"name"` (default): ascending by term name, ignoring case, so `apple` sorts before `Zebra`.
- `"count"` — page count descending, name-ascending tiebreak. On a
  multilingual site, each language's index uses that language's own page
  counts.

**Term feeds are exempt.** With `feed = true`, each term's RSS feed stays
reverse-chronological regardless of `sort_by`, because RSS consumers assume
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
(e.g. `{% for t in page.taxonomies.tech %}`), and also on the page objects
inside `section.pages`, `site.pages`, and term page lists.

## Generated URLs

For a taxonomy named `tags` with term `crystal`:

| URL | Content |
|-----|---------|
| `/tags/` | List of all tags |
| `/tags/crystal/` | Pages tagged "crystal" |

With `paginate_by` set, term pages paginate at `/tags/crystal/page/2/`, `/tags/crystal/page/3/`, … (page 1 stays at `/tags/crystal/`). The pager object is described in [Data Model › Paginator](/templates/data-model/#paginator).

On a multilingual site, each non-default language writes its own term pages
under its prefix (`/ko/tags/crystal/`), listing only that language's pages.
`[languages.<code>] taxonomies` picks which taxonomies a language generates
(every `[[taxonomies]]` name when omitted); see [Multilingual](/features/multilingual/).

## Term Pages from Content

A term page can carry its own title, description and text. Put an `_index.md` in `content/<taxonomy>/<slug>/`, where `<slug>` is the last segment of the term page's URL:

```markdown
+++
title = "Crystal"
description = "Posts about the Crystal language"
image = "/images/crystal.png"

[extra]
icon = "gem"
+++

Crystal is a compiled language with Ruby-like syntax.
```

`content/tags/crystal/_index.md` decorates `/tags/crystal/`. The directory name is the term's URL slug, not its spelling: the term `Rust Lang` lives at `/tags/rust-lang/`, so its file is `content/tags/rust-lang/_index.md`. When two terms share a slug (`C#` and `C++` both slugify to `c`), the second one's page is `/tags/c-2/` and its file is `content/tags/c-2/_index.md`.

On the term page:

- `page.title`, `page.description`, `page.image` and `page.extra` take the file's values. Without a `title`, the generated "Tags: crystal" stays. The `<title>`, og/twitter tags and the term's RSS feed title use the same values.
- `term_content` is the file's rendered body. Markdown, shortcodes, syntax highlighting and `@/` links are processed like any other page, and `[links]` checks report its broken `@/` links and its broken anchors into other pages. Links pointing into the term page itself (`@/tags/crystal/_index.md#part`, or a `#part` link inside the body) are not anchor-checked. `content` stays the generated page list, so existing templates keep working; print `{{ term_content }}` where the text should go.
- `aliases` in the file become redirects to the term page, which is useful when a tag is renamed. An alias that names a generated taxonomy page or one of its `page/N/` pages (N ≥ 2), or that another page already claims, is not written; the build warns. Nothing is generated at `page/1/`, so an alias there is written.
- `template` is ignored (the build warns): term pages always render with `taxonomy_term.html`, falling back to `taxonomy.html`, then `page.html`.
- Keys that shape a section's own page — `in_sitemap`, `in_search_index`, `paginate`, `paginate_by`, `paginate_path`, `pagination_enabled`, `sort_by`, `reverse`, `generate_feeds`, `redirect_to` — do not apply to the term page either; the build warns and names them. Sitemap, pagination, sorting and feeds of term pages are set per taxonomy in `[[taxonomies]]`.
- [`get_taxonomy()`](#get-taxonomy-function) terms get `title` and `description` from the file (default-language files only, since `get_taxonomy()` is a site-wide view). Terms without a file have no `title` key, so use `{{ term.title or term.name }}`.

On a multilingual site each language reads its own file: `content/tags/crystal/_index.ko.md` decorates `/ko/tags/crystal/`.

A file only counts as term metadata when all of these hold:

- it is an `_index` file exactly two levels below `content/`, in a directory named after a configured taxonomy (`content/tags/<dir>/_index.md`);
- the build generates a term page for that taxonomy in the file's language (some published page in that language carries the term and keeps its own URL, i.e. doesn't lose an output-path collision to another page, and `[languages.<code>] taxonomies` doesn't leave the taxonomy out);
- the file would publish at that term page's URL: `<dir>` is the term's URL slug, and no `path` front matter or `[permalinks]` rule moves the section elsewhere.

Such a file is not published as a page of its own. It stays out of the sitemap, feeds, search index, llms.txt and page listings (`section.pages`), so the term URL appears once. `get_section()` still finds it, and its parent's `subsections` still list it, with the term page's URL. If two files match the same term page (`_index.md` beside `_index.markdown`, or `_index.ko.md` beside `_index.ko.markdown`), the `.md` file wins and the build warns about the other.

Any other `_index.md` under `content/tags/` is an ordinary section and publishes as before; `hwaro doctor` notes each one (`taxonomy-term-file-unmatched`), since a directory named after the term's spelling instead of its slug is the usual cause. Pages nested inside a term directory, such as `content/tags/crystal/notes.md`, always publish as ordinary pages.

`content/<taxonomy>/_index.md` (one level up) is different: the generated term list still replaces it at `/tags/`, and the build warns about the replacement as before. Sites use it to put the taxonomy into menus.

## Templates

Both templates receive a ready-made listing as `{{ content }}`: the term list in `taxonomy.html`, the page list in `taxonomy_term.html`. For custom markup, use [`get_taxonomy()`](#get-taxonomy-function) instead of `content`.

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

Custom page list, looking up the current term's pages via `get_taxonomy()`:

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
| term_content | String | Rendered body of the term's `_index.md` (term pages only; empty without one). See [Term Pages from Content](#term-pages-from-content) |

### Term Object

| Property | Type | Description |
|----------|------|-------------|
| name | String | Term name |
| slug | String | URL-safe name |
| pages | Array<Page> | Pages with this term |
| count | Int | Number of pages |
| title | String | Title from the term's `_index.md` (only when that file exists) |
| description | String | Description from the term's `_index.md` (only when that file exists) |

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
  <a href="{{ get_taxonomy_url(kind="tags", term=tag) }}">{{ tag }}</a>
{% endfor %}
</div>
{% endif %}
```

Use `get_taxonomy_url()` (or `term.slug` from `get_taxonomy()`) rather than `{{ tag | slugify }}`: when two terms collide on a slug (`Crystal` and `crystal`), the generator writes `/tags/crystal/` and `/tags/crystal-2/`, and only the function knows which is which.

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
