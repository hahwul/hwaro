+++
title = "Series"
description = "Group posts into ordered series for sequential reading"
weight = 22
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

## Template Variables

Each page in a series has the following variables:

| Variable | Type | Description |
|----------|------|-------------|
| series | string | The series name |
| series_index | int | 1-based position in the series |
| series_pages | array | All pages in the same series (sorted) |

## Usage in Templates

### Series Navigation

```jinja
{% if series %}
<nav class="series-nav">
  <h3>{{ series }}</h3>
  <ol>
    {% for p in series_pages %}
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
{% if series_pages | length > 1 %}
<div class="series-pager">
  {% if series_index > 1 %}
    <a href="{{ series_pages[series_index - 2].url }}">← Previous</a>
  {% endif %}
  <span>Part {{ series_index }} of {{ series_pages | length }}</span>
  {% if series_index < series_pages | length %}
    <a href="{{ series_pages[series_index].url }}">Next →</a>
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

Each post will have `series_pages` containing all three posts in order, and `series_index` set to 1, 2, or 3 respectively.
