+++
title = "Section"
+++

Sections are directories that group related content. They require an `_index.md` file.

## Creating a Section

```
content/
└── blog/
    ├── _index.md     # Required: section index
    ├── first.md      # /blog/first/
    └── second.md     # /blog/second/
```

## Section Index

The `_index.md` defines the section:

```markdown
+++
title = "Blog"
description = "Latest articles"
+++

Welcome to my blog.
```

This content appears at `/blog/`.

## Nested Sections

Sections can be nested:

```
content/
└── docs/
    ├── _index.md           # /docs/
    ├── getting-started/
    │   ├── _index.md       # /docs/getting-started/
    │   └── install.md      # /docs/getting-started/install/
    └── guides/
        ├── _index.md       # /docs/guides/
        └── deploy.md       # /docs/guides/deploy/
```

## Section Template

Sections use `section.html` template by default.

### Available Variables

| Flat Variable | Object Access | Description |
|---------------|---------------|-------------|
| `section_title` | `section.title` | Section title |
| `section_description` | `section.description` | Section description |
| `section_list` | `section.list` | HTML list of pages in section |
| — | `section.pages` | Array of page objects for iteration |
| `content` | — | Section index content |

### Simple Example (using section.list)

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ section.title }}</h1>
{{ content }}

<h2>Pages</h2>
<ul>{{ section.list }}</ul>
{% endblock %}
```

### Advanced Example (using section.pages)

For more control over section page listing, iterate over `section.pages`:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ section.title }}</h1>
{% if section.description %}
<p class="lead">{{ section.description }}</p>
{% endif %}

{{ content }}

<h2>Pages</h2>
<ul>
{% for p in section.pages %}
  <li>
    <a href="{{ p.url }}">{{ p.title }}</a>
    {% if p.date %}<time>{{ p.date }}</time>{% endif %}
    {% if p.description %}<p>{{ p.description }}</p>{% endif %}
  </li>
{% endfor %}
</ul>
{% endblock %}
```

Each page in `section.pages` has these properties:
- `title`, `description`, `url`, `date`, `image`
- `draft`, `toc`, `render`, `is_index`, `generated`, `in_sitemap`, `language`

## Section vs Page

| File | Type | URL |
|------|------|-----|
| `_index.md` | Section index | `/blog/` |
| `index.md` | Regular page | `/blog/` |
| `post.md` | Page in section | `/blog/post/` |

Use `_index.md` when you need a listing of child pages.
