+++
title = "Templates"
description = "Design your site with Jinja2 templates"
+++

Templates define how content becomes HTML. Hwaro uses Crinja, a Jinja2-compatible engine.

## Template Directory

```
templates/
├── base.html           # Base layout
├── page.html           # Regular pages
├── section.html        # Section index pages
├── index.html          # Homepage (optional)
├── taxonomy.html       # Taxonomy listing
├── taxonomy_term.html  # Taxonomy term page
├── 404.html            # Error page
└── shortcodes/         # Shortcode templates
```

## Template Selection

| Content | Template |
|---------|----------|
| `content/index.md` | `index.html` or `page.html` |
| `content/about.md` | `page.html` |
| `content/blog/_index.md` | `section.html` |
| `content/blog/post.md` | `page.html` |
| Taxonomy index | `taxonomy.html` |
| Taxonomy term | `taxonomy_term.html` |

## Quick Example

```jinja
{% extends "base.html" %}

{% block content %}
<article>
  <h1>{{ page.title }}</h1>
  <time>{{ page.date }}</time>
  {{ content | safe }}
</article>
{% endblock %}
```

## Documentation

1. [Data Model](/templates/data-model/) — **Site, Section, Page hierarchy and types**
2. [Syntax](/templates/syntax/) — Template syntax basics
3. [Functions](/templates/functions/) — Built-in template functions
4. [Filters](/templates/filters/) — Text and data transformation