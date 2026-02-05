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
| paginate | int | — | Items per page |
| paginate_path | string | "page" | URL pattern for pages |

### Generated URLs

For a section at `/blog/`:

| Page | URL |
|------|-----|
| 1 | /blog/ |
| 2 | /blog/page/2/ |
| 3 | /blog/page/3/ |

With `paginate_path = "p"`:

| Page | URL |
|------|-----|
| 1 | /blog/ |
| 2 | /blog/p/2/ |
| 3 | /blog/p/3/ |

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
| paginator.paginate_by | Int | Items per page |
| paginator.base_url | String | Base URL for pagination |
| paginator.number_pagers | Int | Total number of pagers (pages) |
| paginator.first | String | URL to first pager |
| paginator.last | String | URL to last pager |
| paginator.previous | String? | URL to previous pager |
| paginator.next | String? | URL to next pager |
| paginator.pages | Array | Array of pages for the current pager |
| paginator.current_index | Int | Current pager index (1-indexed) |
| paginator.total_pages | Int | Total number of items across all pagers |

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
{% if paginator.number_pagers > 1 %}
<nav class="pagination">
  {% if paginator.previous %}
  <a href="{{ paginator.previous }}" class="prev">← Previous</a>
  {% endif %}
  
  <span class="current">
    Page {{ paginator.current_index }} of {{ paginator.number_pagers }}
  </span>
  
  {% if paginator.next %}
  <a href="{{ paginator.next }}" class="next">Next →</a>
  {% endif %}
</nav>
{% endif %}
```

### Full Pagination with Page Numbers

```jinja
{% if paginator.number_pagers > 1 %}
<nav class="pagination">
  {# First page #}
  {% if paginator.current_index > 1 %}
  <a href="{{ paginator.first }}">« First</a>
  {% endif %}
  
  {# Previous #}
  {% if paginator.previous %}
  <a href="{{ paginator.previous }}">‹ Prev</a>
  {% endif %}
  
  {# Current #}
  <span class="current">{{ paginator.current_index }} / {{ paginator.number_pagers }}</span>
  
  {# Next #}
  {% if paginator.next %}
  <a href="{{ paginator.next }}">Next ›</a>
  {% endif %}
  
  {# Last page #}
  {% if paginator.current_index < paginator.number_pagers %}
  <a href="{{ paginator.last }}">Last »</a>
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
