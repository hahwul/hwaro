+++
title = "Functions"
weight = 3
toc = true
+++

Built-in functions for retrieving data and generating URLs in templates.

## Data Retrieval

### get_page()

Retrieve any page by path:

```jinja
{% set about = get_page(path="about.md") %}
{% if about %}
<a href="{{ about.url }}">{{ about.title }}</a>
{% endif %}
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| path | String | Path relative to content/ |

**Returns:** Page? (nil if not found)

**Returned Properties:**

| Property | Type |
|----------|------|
| title | String |
| description | String? |
| url | String |
| date | String? |
| section | String |
| draft | Bool |
| weight | Int |
| summary | String? |
| word_count | Int |
| reading_time | Int |

**Examples:**

```jinja
{# Page in root #}
{% set contact = get_page(path="contact.md") %}

{# Page in section #}
{% set intro = get_page(path="docs/introduction.md") %}
```

---

### get_section()

Retrieve a section and its pages:

```jinja
{% set blog = get_section(path="blog") %}
{% if blog %}
<h2>{{ blog.title }}</h2>
<ul>
{% for p in blog.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>
{% endif %}
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| path | String | Section name or path |

**Returns:** Section? (nil if not found)

**Returned Properties:**

| Property | Type |
|----------|------|
| title | String |
| description | String? |
| url | String |
| pages | Array<Page> |
| pages_count | Int |

**Examples:**

```jinja
{# Top-level section #}
{% set docs = get_section(path="docs") %}

{# Nested section #}
{% set guides = get_section(path="docs/guides") %}

{# Display count #}
<p>{{ docs.pages_count }} articles</p>
```

---

### get_taxonomy()

Access taxonomy terms and their pages:

```jinja
{% set tags = get_taxonomy(kind="tags") %}
{% if tags %}
<ul class="tag-cloud">
{% for term in tags.items %}
  <li>
    <a href="/tags/{{ term.slug }}/">
      {{ term.name }} ({{ term.count }})
    </a>
  </li>
{% endfor %}
</ul>
{% endif %}
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| kind | String | Taxonomy name (e.g., "tags", "categories") |

**Returns:** Taxonomy? (nil if not found)

**Returned Properties:**

| Property | Type |
|----------|------|
| name | String |
| items | Array<Term> |

**Term Properties:**

| Property | Type |
|----------|------|
| name | String |
| slug | String |
| pages | Array<Page> |
| count | Int |

---

### get_taxonomy_url()

Generate URL for a taxonomy term:

```jinja
<a href="{{ get_taxonomy_url(kind='tags', term='crystal') }}">
  Crystal articles
</a>
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| kind | String | Taxonomy name |
| term | String | Term name |

**Returns:** String (absolute URL)

---

## Data Loading

### load_data()

Load external data files (JSON, TOML, YAML, CSV):

```jinja
{% set menu = load_data(path="data/menu.json") %}
{% for item in menu %}
<a href="{{ item.url }}">{{ item.title }}</a>
{% endfor %}
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| path | String | Path to data file |

**Returns:** Parsed data or nil

**Supported Formats:**

| Extension | Format |
|-----------|--------|
| .json | JSON |
| .toml | TOML |
| .yaml, .yml | YAML |
| .csv | CSV (array of arrays) |

**Examples:**

JSON (`data/team.json`):
```json
[
  {"name": "Alice", "role": "Developer"},
  {"name": "Bob", "role": "Designer"}
]
```

```jinja
{% set team = load_data(path="data/team.json") %}
<ul>
{% for member in team %}
  <li>{{ member.name }} - {{ member.role }}</li>
{% endfor %}
</ul>
```

TOML (`data/social.toml`):
```toml
[[links]]
name = "Twitter"
url = "https://twitter.com/example"
```

```jinja
{% set social = load_data(path="data/social.toml") %}
{% for link in social.links %}
<a href="{{ link.url }}">{{ link.name }}</a>
{% endfor %}
```

---

## URL Functions

### url_for()

Generate URL with base_url:

```jinja
<a href="{{ url_for(path='/about/') }}">About</a>
<img src="{{ url_for(path='/images/logo.png') }}">
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| path | String | Path to convert |

**Returns:** String (absolute URL)

---

### now()

Get current datetime:

```jinja
{# Default format #}
<p>Generated: {{ now() }}</p>

{# Custom format #}
<p>Year: {{ now(format="%Y") }}</p>
<p>Date: {{ now(format="%B %d, %Y") }}</p>
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| format | String? | Date format string (optional) |

**Returns:** String

**Format Codes:**

| Code | Description | Example |
|------|-------------|---------|
| %Y | Year | 2025 |
| %m | Month (01-12) | 01 |
| %d | Day (01-31) | 15 |
| %B | Month name | January |
| %b | Month abbr | Jan |
| %H | Hour (00-23) | 14 |
| %M | Minute | 30 |
| %S | Second | 45 |

---

## Best Practices

### Always Check for nil

```jinja
{% set page = get_page(path="featured.md") %}
{% if page %}
{{ page.title }}
{% else %}
<p>Coming soon</p>
{% endif %}
```

### Cache Function Results

```jinja
{# Good: Single lookup #}
{% set blog = get_section(path="blog") %}
<h2>{{ blog.title }}</h2>
<p>{{ blog.pages_count }} posts</p>

{# Avoid: Multiple lookups #}
<h2>{{ get_section(path="blog").title }}</h2>
<p>{{ get_section(path="blog").pages_count }} posts</p>
```

### Organize Data Files

```
data/
├── navigation/
│   ├── main.json
│   └── footer.json
├── team.yaml
└── products.toml
```

---

## See Also

- [Data Model](/templates/data-model/) — Site, Section, Page types
- [Filters](/templates/filters/) — Value transformation
