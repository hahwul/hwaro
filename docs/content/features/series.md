+++
title = "Series"
description = "Group posts into ordered series for sequential reading"
weight = 9
+++

Group related posts into an ordered series so readers can follow content sequentially.

## Configuration

Enable in `config.toml`:

```toml
[series]
enabled = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable series grouping |

## Assigning Posts to a Series

Use front matter to assign a post to a series:

```toml
+++
title = "Part 1: Getting Started"
series = "Building a CLI Tool"
series_weight = 1
+++
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| series | string | — | Series name to assign this post to |
| series_weight | int | 0 | Order within the series (lower = earlier) |

Posts within a series are sorted by `series_weight`, then by date, then by title.

A series is scoped to one language (and, on a [versioned](/features/versioned-docs/) site, one version). On a [multilingual](/features/multilingual/) site, `hello.md` and its translation `hello.ko.md` sharing a `series` name belong to two parallel series, each numbered and linked within its own language.

## Template Variables

Each page in a series has the following variables:

| Variable | Type | Description |
|----------|------|-------------|
| page.series | string | The series name |
| page.series_index | int | 1-based position in the series |
| page.series_pages | array | All pages in the same series (sorted) |

## Usage in Templates

### Series Navigation

```jinja
{% if page.series %}
<nav class="series-nav">
  <h3>{{ page.series }}</h3>
  <ol>
    {% for p in page.series_pages %}
    <li{% if p.url == page.url %} class="current"{% endif %}>
      <a href="{{ p.url }}">{{ p.title }}</a>
    </li>
    {% endfor %}
  </ol>
</nav>
{% endif %}
```

### Previous / Next Links

```jinja
{% if page.series_pages | length > 1 %}
<div class="series-pager">
  {% if page.series_index > 1 %}
    <a href="{{ page.series_pages[page.series_index - 2].url }}">← Previous</a>
  {% endif %}
  <span>Part {{ page.series_index }} of {{ page.series_pages | length }}</span>
  {% if page.series_index < page.series_pages | length %}
    <a href="{{ page.series_pages[page.series_index].url }}">Next →</a>
  {% endif %}
</div>
{% endif %}
```

## Example

Given three posts:

```
content/
  tutorials/
    cli-part1.md   # series = "CLI Tool", series_weight = 1
    cli-part2.md   # series = "CLI Tool", series_weight = 2
    cli-part3.md   # series = "CLI Tool", series_weight = 3
```

Each post will have `page.series_pages` containing all three posts in order, and `page.series_index` set to 1, 2, or 3 respectively.

## See Also

- [Pages](/writing/pages/) — Front matter fields for series
- [Related Posts](/features/related-posts/) — Content recommendations
- [Data Model](/templates/data-model/) — Series template variables
