+++
title = "Templates"
description = "Design your site with Jinja2 templates"
weight = 3
sort_by = "weight"
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
├── shortcodes/         # Shortcode templates
└── hooks/              # Markdown render-element overrides (link/image/heading/codeblock/blockquote/table)
```

The `shortcodes/` directory contains reusable components you can embed in Markdown. See [Writing: Shortcodes](/writing/shortcodes/) for usage and how to create custom shortcodes.

Beyond HTML, a page/section can additionally render sibling `templates/page.<fmt>.jinja` / `templates/section.<fmt>.jinja` files (JSON, XML, TXT, CSV) enabled via `[outputs]`. See [Output Formats](/features/output-formats/).

The `hooks/` directory overrides how individual Markdown elements render. See [Render Hooks](/templates/render-hooks/).

## Template Selection

| Content | Template |
|---------|----------|
| content/index.md | index.html or page.html |
| content/about.md | page.html |
| content/blog/_index.md | section.html |
| content/blog/post.md | the section's `page_template`, else page.html |
| Taxonomy index | taxonomy.html, else page.html |
| Taxonomy term | taxonomy_term.html, else taxonomy.html, else page.html |

A `template` key in a page's or section's front matter overrides this choice. If the named template does not exist, the build warns and falls back to the default above.

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
