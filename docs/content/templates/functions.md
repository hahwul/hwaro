+++
title = "Template Functions"
description = "Built-in template functions for data retrieval and manipulation"
toc = true
weight = 5
+++

Hwaro provides built-in template functions for retrieving data, generating URLs, and loading external files.

## Data Retrieval Functions

### get_page()

Retrieve any page's data by path:

```jinja
{% set about = get_page(path="about.md") %}
{% if about %}
<div class="featured">
  <h3>{{ about.title }}</h3>
  <p>{{ about.description }}</p>
  <a href="{{ about.url }}">Read more</a>
</div>
{% endif %}
```

**Parameters:**
- `path` (string): Path to the page, relative to `content/`

**Returns:** Page object or nil

**Page object properties:**
- `path` - File path
- `title` - Page title
- `description` - Page description
- `url` - Page URL
- `date` - Publication date
- `section` - Section name
- `draft` - Is draft
- `weight` - Sort weight
- `summary` - Content summary
- `word_count` - Word count
- `reading_time` - Reading time (minutes)

**Examples:**

```jinja
{# Get a specific page #}
{% set contact = get_page(path="contact.md") %}

{# Get a page in a section #}
{% set intro = get_page(path="docs/introduction.md") %}

{# Get by URL path #}
{% set post = get_page(path="/blog/my-post/") %}
```

### get_section()

Retrieve a section's data and pages:

```jinja
{% set blog = get_section(path="blog") %}
{% if blog %}
<h2>Latest from {{ blog.title }}</h2>
<ul>
{% for page in blog.pages %}
  <li>
    <a href="{{ page.url }}">{{ page.title }}</a>
    <time>{{ page.date }}</time>
  </li>
{% endfor %}
</ul>
{% endif %}
```

**Parameters:**
- `path` (string): Section name or path

**Returns:** Section object or nil

**Section object properties:**
- `path` - File path
- `name` - Section name
- `title` - Section title
- `description` - Section description
- `url` - Section URL
- `pages` - Array of page objects
- `pages_count` - Number of pages

**Examples:**

```jinja
{# Get section by name #}
{% set docs = get_section(path="docs") %}

{# Get nested section #}
{% set guides = get_section(path="docs/guides") %}

{# Display section info #}
{% if docs %}
<aside class="sidebar">
  <h3>{{ docs.title }}</h3>
  <p>{{ docs.pages_count }} articles</p>
</aside>
{% endif %}
```

### get_taxonomy()

Access taxonomy terms and their pages:

```jinja
{% set tags = get_taxonomy(kind="tags") %}
{% if tags %}
<h3>Tags</h3>
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
- `kind` (string): Taxonomy name (e.g., "tags", "categories", "authors")

**Returns:** Taxonomy object or nil

**Taxonomy object properties:**
- `name` - Taxonomy name
- `items` - Array of term objects

**Term object properties:**
- `name` - Term name
- `slug` - URL-safe slug
- `pages` - Array of pages with this term
- `count` - Number of pages

**Examples:**

```jinja
{# Get categories #}
{% set categories = get_taxonomy(kind="categories") %}

{# Display popular tags (by count) #}
{% set tags = get_taxonomy(kind="tags") %}
{% if tags %}
{% for term in tags.items | sort_by(attribute="count", reverse=true) %}
  <span class="tag">{{ term.name }}</span>
{% endfor %}
{% endif %}

{# Show pages for a specific term #}
{% set tags = get_taxonomy(kind="tags") %}
{% for term in tags.items %}
  {% if term.name == "crystal" %}
  <h4>Crystal articles:</h4>
  <ul>
  {% for page in term.pages %}
    <li><a href="{{ page.url }}">{{ page.title }}</a></li>
  {% endfor %}
  </ul>
  {% endif %}
{% endfor %}
```

### get_taxonomy_url()

Generate URL for a taxonomy term:

```jinja
<a href="{{ get_taxonomy_url(kind='tags', term='crystal') }}">
  Crystal articles
</a>

{# Generates: https://example.com/tags/crystal/ #}
```

**Parameters:**
- `kind` (string): Taxonomy name
- `term` (string): Term name

**Returns:** Absolute URL string

## Data Loading Functions

### load_data()

Load external data files (JSON, TOML, YAML, CSV):

```jinja
{% set menu = load_data(path="data/menu.json") %}
{% if menu %}
<nav>
{% for item in menu %}
  <a href="{{ item.url }}">{{ item.title }}</a>
{% endfor %}
</nav>
{% endif %}
```

**Parameters:**
- `path` (string): Path to data file

**Returns:** Parsed data or nil

**Supported formats:**
- `.json` - JSON files
- `.toml` - TOML files
- `.yaml` / `.yml` - YAML files
- `.csv` - CSV files (as array of arrays)

**Examples:**

#### JSON Data

`data/team.json`:
```json
[
  {"name": "Alice", "role": "Developer"},
  {"name": "Bob", "role": "Designer"}
]
```

```jinja
{% set team = load_data(path="data/team.json") %}
<ul class="team">
{% for member in team %}
  <li>{{ member.name }} - {{ member.role }}</li>
{% endfor %}
</ul>
```

#### TOML Data

`data/social.toml`:
```toml
[[links]]
name = "Twitter"
url = "https://twitter.com/example"

[[links]]
name = "GitHub"
url = "https://github.com/example"
```

```jinja
{% set social = load_data(path="data/social.toml") %}
<div class="social-links">
{% for link in social.links %}
  <a href="{{ link.url }}">{{ link.name }}</a>
{% endfor %}
</div>
```

#### YAML Data

`data/config.yaml`:
```yaml
features:
  - name: Fast
    icon: rocket
  - name: Secure
    icon: lock
```

```jinja
{% set config = load_data(path="data/config.yaml") %}
<ul class="features">
{% for feature in config.features %}
  <li>
    <i class="icon-{{ feature.icon }}"></i>
    {{ feature.name }}
  </li>
{% endfor %}
</ul>
```

#### CSV Data

`data/prices.csv`:
```csv
Product,Price,Stock
Widget,29.99,100
Gadget,49.99,50
```

```jinja
{% set prices = load_data(path="data/prices.csv") %}
<table>
  <tr>
  {% for header in prices[0] %}
    <th>{{ header }}</th>
  {% endfor %}
  </tr>
  {% for row in prices[1:] %}
  <tr>
    {% for cell in row %}
    <td>{{ cell }}</td>
    {% endfor %}
  </tr>
  {% endfor %}
</table>
```

## URL Functions

### url_for()

Generate URL with base_url:

```jinja
<a href="{{ url_for(path='/about/') }}">About</a>
<img src="{{ url_for(path='/images/logo.png') }}">
```

**Parameters:**
- `path` (string): Path to convert

**Returns:** Absolute URL string

### now()

Get current datetime:

```jinja
{# Default format: YYYY-MM-DD HH:MM:SS #}
<p>Generated: {{ now() }}</p>

{# Custom format #}
<p>Year: {{ now(format="%Y") }}</p>
<p>Date: {{ now(format="%B %d, %Y") }}</p>
```

**Parameters:**
- `format` (string, optional): Date format string

**Returns:** Formatted datetime string

## Image Functions

### resize_image()

Placeholder for image resizing (returns original path):

```jinja
{% set img = resize_image(path="/images/photo.jpg", width=800, height=600) %}
<img src="{{ img.url }}" width="{{ img.width }}" height="{{ img.height }}">
```

**Parameters:**
- `path` (string): Image path
- `width` (int): Target width
- `height` (int): Target height
- `op` (string, optional): Operation type (fill, fit, etc.)

**Returns:** Object with `url`, `width`, `height`

**Note:** Full image processing is not yet implemented. Currently returns the original image path.

## Best Practices

### Null Checking

Always check if the function returns data:

```jinja
{% set page = get_page(path="featured.md") %}
{% if page %}
  {# Safe to use page properties #}
  {{ page.title }}
{% else %}
  {# Handle missing page #}
  <p>Featured content coming soon</p>
{% endif %}
```

### Caching Data

Assign to variables to avoid repeated lookups:

```jinja
{# Good: Single lookup #}
{% set blog = get_section(path="blog") %}
<h2>{{ blog.title }}</h2>
<p>{{ blog.pages_count }} posts</p>
{% for page in blog.pages %}...{% endfor %}

{# Avoid: Multiple lookups #}
<h2>{{ get_section(path="blog").title }}</h2>
<p>{{ get_section(path="blog").pages_count }} posts</p>
```

### Data File Organization

Keep data files organized:

```
data/
├── navigation/
│   ├── main.json
│   └── footer.json
├── team.yaml
├── products.toml
└── pricing.csv
```

```jinja
{% set main_nav = load_data(path="data/navigation/main.json") %}
{% set footer_nav = load_data(path="data/navigation/footer.json") %}
```

## See Also

- [Template Variables](/templates/variables/)
- [Filters](/templates/filters/)
