+++
title = "Overview"
+++

Templates define how your content is rendered into HTML. Hwaro uses Crinja, a Jinja2-compatible template engine.

If you’re looking for a “build and ship” walkthrough first, start here: [Guide](/guide/).

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

## Basic Syntax

### Variables

```jinja
{{ page_title }}
{{ site_title }}
{{ content }}
```

### Conditionals

```jinja
{% if page_description %}
<meta name="description" content="{{ page_description }}">
{% endif %}
```

### Template Inheritance

Base template:

```jinja
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ site_title }}{% endblock %}</title>
</head>
<body>
  {% block content %}{% endblock %}
</body>
</html>
```

Child template:

```jinja
{% extends "base.html" %}

{% block title %}{{ page_title }} - {{ site_title }}{% endblock %}

{% block content %}
<article>{{ content }}</article>
{% endblock %}
```

### Includes

```jinja
{% include "partials/nav.html" %}
{% include "partials/footer.html" %}
```

## In This Section

- [Variables](/templates/variables/) — Available template variables
- [Filters & Tests](/templates/filters/) — Data transformation and conditionals
- [Pagination](/templates/pagination/) — Paginating section listings
- [Built-in Templates](/templates/built-in/) — Default template structure
