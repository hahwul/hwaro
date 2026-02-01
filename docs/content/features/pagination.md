+++
title = "Pagination"
weight = 4
+++

Split large content lists into multiple pages.

## Configuration

### Section Pagination

Enable in section front matter:

```toml
+++
title = "Blog"
paginate = 10
paginate_path = "page"
+++
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `paginate` | int | — | Items per page |
| `paginate_path` | string | `"page"` | URL pattern for pages |

### Generated URLs

For a section at `/blog/`:

| Page | URL |
|------|-----|
| 1 | `/blog/` |
| 2 | `/blog/page/2/` |
| 3 | `/blog/page/3/` |

With `paginate_path = "p"`:

| Page | URL |
|------|-----|
| 1 | `/blog/` |
| 2 | `/blog/p/2/` |
| 3 | `/blog/p/3/` |

## Template Variables

### pagination

Pre-rendered pagination HTML:

```jinja
{{ pagination | safe }}
```

### paginator

Pagination object for custom rendering:

| Property | Type | Description |
|----------|------|-------------|
| `paginator.current_page` | `Int` | Current page number |
| `paginator.total_pages` | `Int` | Total number of pages |
| `paginator.per_page` | `Int` | Items per page |
| `paginator.total_items` | `Int` | Total items |
| `paginator.first_page` | `String` | URL to first page |
| `paginator.last_page` | `String` | URL to last page |
| `paginator.previous_page` | `String?` | URL to previous page |
| `paginator.next_page` | `String?` | URL to next page |

## Template Examples

### Simple Navigation

Use the pre-rendered `pagination` variable:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ section.title }}</h1>

<ul>
{% for p in section.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>

{{ pagination | safe }}
{% endblock %}
```

### Custom Pagination

Build your own pagination UI:

```jinja
{% if paginator.total_pages > 1 %}
<nav class="pagination">
  {% if paginator.previous_page %}
  <a href="{{ paginator.previous_page }}" class="prev">← Previous</a>
  {% endif %}
  
  <span class="current">
    Page {{ paginator.current_page }} of {{ paginator.total_pages }}
  </span>
  
  {% if paginator.next_page %}
  <a href="{{ paginator.next_page }}" class="next">Next →</a>
  {% endif %}
</nav>
{% endif %}
```

### Full Pagination with Page Numbers

```jinja
{% if paginator.total_pages > 1 %}
<nav class="pagination">
  {# First page #}
  {% if paginator.current_page > 1 %}
  <a href="{{ paginator.first_page }}">« First</a>
  {% endif %}
  
  {# Previous #}
  {% if paginator.previous_page %}
  <a href="{{ paginator.previous_page }}">‹ Prev</a>
  {% endif %}
  
  {# Current #}
  <span class="current">{{ paginator.current_page }} / {{ paginator.total_pages }}</span>
  
  {# Next #}
  {% if paginator.next_page %}
  <a href="{{ paginator.next_page }}">Next ›</a>
  {% endif %}
  
  {# Last page #}
  {% if paginator.current_page < paginator.total_pages %}
  <a href="{{ paginator.last_page }}">Last »</a>
  {% endif %}
</nav>
{% endif %}
```

## Taxonomy Pagination

Taxonomies also support pagination in `config.toml`:

```toml
[[taxonomies]]
name = "tags"
paginate = 20
```

## CSS Example

```css
.pagination {
  display: flex;
  gap: 1rem;
  justify-content: center;
  margin: 2rem 0;
}

.pagination a {
  padding: 0.5rem 1rem;
  border: 1px solid #ddd;
  text-decoration: none;
}

.pagination a:hover {
  background: #f0f0f0;
}

.pagination .current {
  padding: 0.5rem 1rem;
  font-weight: bold;
}
```

## See Also

- [Sections](/writing/sections/) — Section configuration
- [Taxonomies](/writing/taxonomies/) — Taxonomy pagination
- [Data Model](/templates/data-model/) — Section variables