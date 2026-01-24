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

Available variables:

| Variable | Description |
|----------|-------------|
| `section_title` | Section title |
| `section_description` | Section description |
| `section_list` | HTML list of pages in section |
| `content` | Section index content |

Example template:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ section_title }}</h1>
{{ content }}

<h2>Pages</h2>
<ul>{{ section_list }}</ul>
{% endblock %}
```

## Section vs Page

| File | Type | URL |
|------|------|-----|
| `_index.md` | Section index | `/blog/` |
| `index.md` | Regular page | `/blog/` |
| `post.md` | Page in section | `/blog/post/` |

Use `_index.md` when you need a listing of child pages.