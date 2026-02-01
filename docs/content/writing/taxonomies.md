+++
title = "Taxonomies"
weight = 4
+++

Taxonomies organize content into groups like tags, categories, or authors.

## Configuration

Define taxonomies in `config.toml`:

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate = 10

[[taxonomies]]
name = "categories"
feed = true

[[taxonomies]]
name = "authors"
```

| Key | Type | Description |
|-----|------|-------------|
| `name` | string | Taxonomy name (used in front matter) |
| `feed` | bool | Generate RSS feed for each term |
| `paginate` | int | Pages per pagination page |

## Using Taxonomies

Assign terms in front matter:

```markdown
+++
title = "My Post"
tags = ["crystal", "tutorial"]
categories = ["Programming"]
authors = ["Alice"]
+++
```

## Generated URLs

For a taxonomy named `tags` with term `crystal`:

| URL | Content |
|-----|---------|
| `/tags/` | List of all tags |
| `/tags/crystal/` | Pages tagged "crystal" |

## Templates

### Taxonomy Index

`templates/taxonomy.html` — List of all terms:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ taxonomy_name | capitalize }}</h1>
<ul>
{% for term in taxonomy_terms %}
  <li>
    <a href="/{{ taxonomy_name }}/{{ term.slug }}/">
      {{ term.name }} ({{ term.count }})
    </a>
  </li>
{% endfor %}
</ul>
{% endblock %}
```

### Taxonomy Term

`templates/taxonomy_term.html` — Pages for a specific term:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ taxonomy_name }}: {{ taxonomy_term }}</h1>
<ul>
{% for p in taxonomy_pages %}
  <li>
    <a href="{{ p.url }}">{{ p.title }}</a>
    <time>{{ p.date }}</time>
  </li>
{% endfor %}
</ul>
{% endblock %}
```

## Template Variables

### In taxonomy.html

| Variable | Type | Description |
|----------|------|-------------|
| `taxonomy_name` | string | Taxonomy name ("tags") |
| `taxonomy_terms` | array | List of term objects |

### In taxonomy_term.html

| Variable | Type | Description |
|----------|------|-------------|
| `taxonomy_name` | string | Taxonomy name |
| `taxonomy_term` | string | Current term name |
| `taxonomy_pages` | array | Pages with this term |

### Term Object

| Property | Type | Description |
|----------|------|-------------|
| `name` | string | Term name |
| `slug` | string | URL-safe name |
| `count` | int | Number of pages |

## get_taxonomy() Function

Access taxonomy data anywhere:

```jinja
{% set tags = get_taxonomy(kind="tags") %}
{% if tags %}
<div class="tag-cloud">
{% for term in tags.items %}
  <a href="/tags/{{ term.slug }}/">{{ term.name }}</a>
{% endfor %}
</div>
{% endif %}
```

## get_taxonomy_url() Function

Generate taxonomy term URL:

```jinja
<a href="{{ get_taxonomy_url(kind='tags', term='crystal') }}">
  Crystal articles
</a>
```

## Common Patterns

### Tag Cloud

```jinja
{% set tags = get_taxonomy(kind="tags") %}
<div class="tags">
{% for term in tags.items %}
  <a href="/tags/{{ term.slug }}/" 
     class="tag count-{{ term.count }}">
    {{ term.name }}
  </a>
{% endfor %}
</div>
```

### Display Page Tags

```jinja
{% if page.extra.tags %}
<div class="post-tags">
{% for tag in page.extra.tags %}
  <a href="/tags/{{ tag | slugify }}/">{{ tag }}</a>
{% endfor %}
</div>
{% endif %}
```

### Category Navigation

```jinja
{% set categories = get_taxonomy(kind="categories") %}
<nav class="categories">
{% for cat in categories.items %}
  <a href="/categories/{{ cat.slug }}/">
    {{ cat.name }} ({{ cat.count }})
  </a>
{% endfor %}
</nav>
```
