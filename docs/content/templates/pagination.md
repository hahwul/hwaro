+++
title = "Pagination"
toc = true
+++

Paginate section listing pages (e.g., `/posts/`, `/blog/`) and render navigation in `section.html`.

## Enable Pagination

In `config.toml`:

```toml
[pagination]
enabled = true
per_page = 10
```

## Per-Section Overrides

In a section `_index.md` front matter:

```toml
+++
title = "Posts"
paginate = 10
pagination_enabled = true
sort_by = "date"   # "date" | "title" | "weight"
reverse = false
+++
```

## Template Usage

`section_list` contains the `<li>...</li>` items for the current page, and `pagination` contains the `<nav>` element.

```jinja
<ul class="section-list">
  {{ section_list }}
</ul>

{{ pagination }}
```
