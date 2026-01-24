+++
title = "Taxonomies"
toc = true
+++

Taxonomies are classification systems for organizing content (tags, categories, authors, etc.).

## Configuration

Define taxonomies in `config.toml`:

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate_by = 10

[[taxonomies]]
name = "categories"

[[taxonomies]]
name = "authors"
feed = true
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `name` | required | Taxonomy name |
| `feed` | `false` | Generate RSS feed per term |
| `paginate_by` | `0` | Items per page (0 = no pagination) |
| `sitemap` | `true` | Include in sitemap |

## Using in Content

Add taxonomy terms in front matter:

```markdown
+++
title = "My Post"
tags = ["crystal", "tutorial", "beginner"]
categories = ["Programming"]
authors = ["Jane Doe"]
+++
```

## Generated Pages

For a `tags` taxonomy with terms "crystal" and "web":

| URL | Description |
|-----|-------------|
| `/tags/` | List of all tags |
| `/tags/crystal/` | Posts tagged "crystal" |
| `/tags/web/` | Posts tagged "web" |
| `/tags/crystal/rss.xml` | RSS feed (if `feed = true`) |

## Pagination

With `paginate_by = 10`:

| URL | Content |
|-----|---------|
| `/tags/crystal/` | Items 1-10 |
| `/tags/crystal/page/2/` | Items 11-20 |
| `/tags/crystal/page/3/` | Items 21-30 |

## Templates

### Taxonomy Index (`taxonomy.html`)

Lists all terms in a taxonomy:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ taxonomy_name | capitalize }}</h1>
<ul>
  {{ content }}
</ul>
{% endblock %}
```

### Taxonomy Term (`taxonomy_term.html`)

Lists content with a specific term:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ taxonomy_term }}</h1>
{{ content }}
{% endblock %}
```

## Common Taxonomies

### Tags

Fine-grained keywords:

```toml
[[taxonomies]]
name = "tags"
feed = true
```

```markdown
tags = ["api", "rest", "tutorial"]
```

### Categories

Broad groupings:

```toml
[[taxonomies]]
name = "categories"
```

```markdown
categories = ["Backend", "Documentation"]
```

### Authors

Content creators:

```toml
[[taxonomies]]
name = "authors"
feed = true
```

```markdown
authors = ["John Doe", "Jane Smith"]
```

### Series

Multi-part content:

```toml
[[taxonomies]]
name = "series"
```

```markdown
series = ["Building a Blog"]
```

## Styling

Tag cloud example:

```css
.taxonomy-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  list-style: none;
  padding: 0;
}

.taxonomy-list a {
  display: inline-block;
  padding: 0.25rem 0.75rem;
  background: var(--bg-subtle);
  border-radius: 100px;
  font-size: 0.875rem;
  text-decoration: none;
}

.taxonomy-list a:hover {
  background: var(--primary);
  color: white;
}
```

## Best Practices

- Use consistent naming: "JavaScript" not "javascript", "Javascript", "JS"
- Limit tags to relevant terms (3-5 per post)
- Use categories for broad topics, tags for specifics
- Consider RSS feeds for popular taxonomies