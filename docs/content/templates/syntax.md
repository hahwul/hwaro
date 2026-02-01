+++
title = "Syntax"
weight = 2
toc = true
+++

Hwaro uses Crinja, a Jinja2-compatible template engine. This page covers the essential syntax.

## Variables

Print values with double braces:

```jinja
{{ page.title }}
{{ site.description }}
{{ content }}
```

## Comments

```jinja
{# This is a comment #}
```

## Conditionals

```jinja
{% if page.description %}
<meta name="description" content="{{ page.description }}">
{% endif %}
```

With else:

```jinja
{% if page.draft %}
<span class="badge">Draft</span>
{% else %}
<span class="badge">Published</span>
{% endif %}
```

With elif:

```jinja
{% if page.section == "blog" %}
<article class="post">{{ content | safe }}</article>
{% elif page.section == "docs" %}
<div class="documentation">{{ content | safe }}</div>
{% else %}
<main>{{ content | safe }}</main>
{% endif %}
```

## Loops

```jinja
{% for p in section.pages %}
<li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
```

With index:

```jinja
{% for tag in page.tags %}
{% if not loop.first %}, {% endif %}
{{ tag }}
{% endfor %}
```

Loop variables:

| Variable | Description |
|----------|-------------|
| loop.index | Current iteration (1-based) |
| loop.index0 | Current iteration (0-based) |
| loop.first | True on first iteration |
| loop.last | True on last iteration |
| loop.length | Total items |

## Template Inheritance

### Base Template

`templates/base.html`:

```jinja
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ site.title }}{% endblock %}</title>
  {{ highlight_css | safe }}
</head>
<body>
  {% block content %}{% endblock %}
  {{ highlight_js | safe }}
</body>
</html>
```

### Child Template

`templates/page.html`:

```jinja
{% extends "base.html" %}

{% block title %}{{ page.title }} - {{ site.title }}{% endblock %}

{% block content %}
<article>
  <h1>{{ page.title }}</h1>
  {{ content | safe }}
</article>
{% endblock %}
```

## Includes

Include partial templates:

```jinja
{% include "partials/header.html" %}
<main>{{ content | safe }}</main>
{% include "partials/footer.html" %}
```

## Variables

Set variables:

```jinja
{% set author = page.authors | first %}
<span>By {{ author }}</span>
```

## Filters

Transform values with the pipe operator:

```jinja
{{ page.title | upper }}
{{ content | safe }}
{{ page.date | date("%B %d, %Y") }}
{{ page.authors | join(", ") }}
```

See [Filters](/templates/filters/) for all available filters.

## Tests

Evaluate conditions:

```jinja
{% if page.url is startswith("/blog/") %}
<span>Blog post</span>
{% endif %}

{% if page.description is empty %}
<meta name="description" content="{{ site.description }}">
{% endif %}
```

See [Filters](/templates/filters/) for all available tests.

## Whitespace Control

Trim whitespace with minus signs:

```jinja
{%- if condition -%}
trimmed
{%- endif -%}
```

## Raw Blocks

Output literal Jinja syntax:

```jinja
{% raw %}
{{ this will not be parsed }}
{% endraw %}
```

## Operators

### Comparison

| Operator | Description |
|----------|-------------|
| `==` | Equal |
| `!=` | Not equal |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less or equal |
| `>=` | Greater or equal |

### Logical

| Operator | Description |
|----------|-------------|
| `and` | Both true |
| `or` | Either true |
| `not` | Negation |

```jinja
{% if page.section == "blog" and not page.draft %}
<article>{{ content | safe }}</article>
{% endif %}
```

### Membership

```jinja
{% if "tutorial" in page.tags %}
<span class="badge">Tutorial</span>
{% endif %}
```

## Common Patterns

### Active Navigation

```jinja
<nav>
  <a href="/"{% if page.url == "/" %} class="active"{% endif %}>Home</a>
  <a href="/blog/"{% if page.section == "blog" %} class="active"{% endif %}>Blog</a>
</nav>
```

### Conditional Meta Tags

```jinja
<head>
  {% if page.description %}
  <meta name="description" content="{{ page.description }}">
  {% endif %}
  {{ og_all_tags | safe }}
</head>
```

### Section-Based Layout

```jinja
<body data-section="{{ page.section }}">
  {% if page.section == "docs" %}
  {% include "partials/sidebar.html" %}
  {% endif %}
  
  <main>{{ content | safe }}</main>
</body>
```

### Loop with Empty Check

```jinja
{% if section.pages %}
<ul>
{% for p in section.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>
{% else %}
<p>No articles yet.</p>
{% endif %}
```

## See Also

- [Data Model](/templates/data-model/) — Available variables
- [Functions](/templates/functions/) — Built-in functions
- [Filters](/templates/filters/) — Filters and tests
