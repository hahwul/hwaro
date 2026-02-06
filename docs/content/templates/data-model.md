+++
title = "Data Model"
weight = 1
toc = true
+++

Hwaro's template system centers on three core types: **Site**, **Section**, and **Page**. Understanding their hierarchy is essential for building templates.

## Hierarchy

```
Site
├── Config (title, base_url, ...)
├── Pages[] (standalone pages)
├── Sections[]
│   ├── Pages[] (pages in section)
│   └── Subsections[]
│       ├── Pages[]
│       └── Subsections[] (recursive)
└── Taxonomies{}
    └── Terms{}
        └── Pages[]
```

### Relationships

- A **Site** contains multiple **Sections** and standalone **Pages**
- A **Section** contains **Pages** and child **Subsections**
- **Subsections** can nest indefinitely
- **Taxonomies** group **Pages** by terms

## Site

The root container. Configured in `config.toml`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| site.title | String | Site title |
| site.description | String | Site description |
| site.base_url | String | Base URL (no trailing slash) |
| site.pages | Array<Page> | All non-section pages |
| site.sections | Array<Section> | All section index pages |
| site.taxonomies | Object | All taxonomy groups and terms |

### Flat Aliases

| Variable | Equivalent |
|----------|------------|
| site_title | site.title |
| site_description | site.description |
| base_url | site.base_url |

### Example

```jinja
<title>{{ site.title }}</title>
<link rel="canonical" href="{{ site.base_url }}{{ page.url }}">
```

---

## Section

A directory with `_index.md` that groups related content.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| section.title | String | Section title |
| section.description | String? | Section description |
| section.pages | Array<Page> | Pages in this section |
| section.pages_count | Int | Number of pages |
| section.list | String | Pre-rendered HTML list (`section_list`) |
| section.subsections | Array<Section> | Child sections |
| section.assets | Array<String> | Static files in section |
| section.page_template | String? | Default template for pages |
| section.paginate_path | String | Pagination URL pattern |
| section.redirect_to | String? | Redirect URL |

For the current section URL in `section.html`, use `page.url`.

### Flat Aliases

| Variable | Equivalent |
|----------|------------|
| section_title | section.title |
| section_description | section.description |
| section_list | Pre-rendered HTML list of pages |

### From Front Matter

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| sort_by | String? | "date" | Sort by: date, weight, title |
| reverse | Bool? | false | Reverse sort order |
| paginate | Int? | — | Pages per page |
| transparent | Bool | false | Pass pages to parent |
| generate_feeds | Bool | false | Generate RSS feed |

### Iterating Pages

```jinja
{% for p in section.pages %}
<article>
  <h2><a href="{{ p.url }}">{{ p.title }}</a></h2>
  <time>{{ p.date }}</time>
  {% if p.description %}
  <p>{{ p.description }}</p>
  {% endif %}
</article>
{% endfor %}
```

### Iterating Subsections

```jinja
{% for sub in section.subsections %}
<div class="category">
  <a href="{{ sub.url }}">{{ sub.title }}</a>
  <span>({{ sub.pages_count }} articles)</span>
</div>
{% endfor %}
```

### Using section_list

For simple listings, use the pre-rendered HTML:

```jinja
<ul>{{ section_list | safe }}</ul>
```

---

## Page

An individual content file (`.md`).

### Core Properties

| Property | Type | Description |
|----------|------|-------------|
| page.title | String | Page title |
| page.description | String? | Page description |
| page.url | String | Relative URL path |
| page.permalink | String? | Absolute URL with base_url |
| page.section | String | Parent section name |
| page.date | String? | Publication date (YYYY-MM-DD) |
| page.updated | String? | Last updated date |
| page.language | String | Effective language code |
| page.translations | Array<TranslationLink> | Language variants |

Rendered HTML content is available as the top-level `content` variable.

### Metadata Properties

| Property | Type | Description |
|----------|------|-------------|
| page.draft | Bool | Is draft |
| page.weight | Int | Sort weight |
| page.image | String? | Featured image path |
| page.authors | Array<String> | Author names |
| page.extra | Object | Custom front matter fields |

### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| page.word_count | Int | Word count |
| page.reading_time | Int | Reading time (minutes) |
| page.summary | String? | Content before <!-- more --> |
| page.assets | Array<String> | Static files in page bundle |

### Boolean Flags

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| page.toc | Bool | false | Show table of contents |
| page.render | Bool | true | Should render |
| page.is_index | Bool | — | Is index file |
| page.generated | Bool | false | Auto-generated page |
| page.in_sitemap | Bool | true | Include in sitemap |
| page.in_search_index | Bool | true | Include in search |

### Navigation Properties

| Property | Type | Description |
|----------|------|-------------|
| page.lower | Page? | Previous page in section |
| page.higher | Page? | Next page in section |
| page.ancestors | Array<Page> | Parent section chain |
| page.translations | Array<TranslationLink> | Language variants |

### Custom Metadata

| Property | Type | Description |
|----------|------|-------------|
| page.extra | Object | Custom front matter fields |

### Flat Aliases

| Variable | Equivalent |
|----------|------------|
| page_title | page.title |
| page_description | page.description |
| page_url | page.url |
| page_section | page.section |
| page_date | page.date |
| page_image | page.image |
| page_summary | page.summary |
| page_word_count | page.word_count |
| page_reading_time | page.reading_time |
| page_permalink | page.permalink |
| page_authors | page.authors |
| page_weight | page.weight |
| page_language | page.language |
| page_translations | page.translations |
| taxonomy_name | Current taxonomy name (taxonomy pages) |
| taxonomy_term | Current taxonomy term (taxonomy term pages) |
| content | Rendered HTML content |

---

## Navigation Objects

### page.lower / page.higher

| Property | Type | Description |
|----------|------|-------------|
| .title | String | Page title |
| .url | String | Page URL |
| .description | String? | Page description |
| .date | String? | Page date |

```jinja
<nav class="post-nav">
  {% if page.lower %}
  <a href="{{ page.lower.url }}">← {{ page.lower.title }}</a>
  {% endif %}
  
  {% if page.higher %}
  <a href="{{ page.higher.url }}">{{ page.higher.title }} →</a>
  {% endif %}
</nav>
```

### page.ancestors

Parent sections for breadcrumbs:

```jinja
<nav class="breadcrumbs">
  <a href="/">Home</a>
  {% for ancestor in page.ancestors %}
  / <a href="{{ ancestor.url }}">{{ ancestor.title }}</a>
  {% endfor %}
  / <span>{{ page.title }}</span>
</nav>
```

### page.translations

| Property | Type | Description |
|----------|------|-------------|
| .code | String | Language code (e.g., "en") |
| .url | String | Translated page URL |
| .title | String | Title in that language |
| .is_current | Bool | Current page's language |
| .is_default | Bool | Default language |

```jinja
{% if page.translations %}
<nav class="lang-switcher">
{% for t in page.translations %}
  {% if t.is_current %}
  <span>{{ t.code | upper }}</span>
  {% else %}
  <a href="{{ t.url }}">{{ t.code | upper }}</a>
  {% endif %}
{% endfor %}
</nav>
{% endif %}
```

---

## Accessing page.extra

Custom metadata from front matter:

```markdown
+++
title = "Review"

[extra]
rating = 4.5
featured = true
pros = ["Fast", "Reliable"]
+++
```

```jinja
{% if page.extra.featured %}
<span class="badge">Featured</span>
{% endif %}

<div class="rating">{{ page.extra.rating }} / 5</div>

<ul>
{% for pro in page.extra.pros %}
  <li>{{ pro }}</li>
{% endfor %}
</ul>
```

---

### Time Variables

| Variable | Type | Description |
|----------|------|-------------|
| current_year | Int | Current year (e.g., 2025) |
| current_date | String | Current date (YYYY-MM-DD) |
| current_datetime | String | Current datetime |

```jinja
<footer>&copy; {{ current_year }} {{ site.title }}</footer>
```

---

### SEO Variables

| Variable | Description |
|----------|-------------|
| og_tags | OpenGraph meta tags |
| twitter_tags | Twitter Card meta tags |
| og_all_tags | Both OG and Twitter tags |
| canonical_tag | Canonical link tag |
| hreflang_tags | Hreflang alternate link tags (multilingual) |

```jinja
<head>
  {{ og_all_tags | safe }}
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
</head>
```

---

### Asset Variables

| Variable | Description |
|----------|-------------|
| highlight_css | Syntax highlighting CSS |
| highlight_js | Syntax highlighting JS |
| highlight_tags | Both CSS and JS |
| auto_includes_css | Auto-included CSS |
| auto_includes_js | Auto-included JS |
| auto_includes | All auto-includes |

```jinja
<head>
  {{ highlight_css | safe }}
  {{ auto_includes_css | safe }}
</head>
<body>
  ...
  {{ highlight_js | safe }}
  {{ auto_includes_js | safe }}
</body>
```

---

### Table of Contents

| Variable | Type | Description |
|----------|------|-------------|
| toc | String | Generated TOC HTML |
| toc_obj.html | String | Same TOC HTML in object form |

Only available when `toc = true` in front matter:

```jinja
{% if page.toc %}
<aside class="toc">
  {{ toc | safe }}
</aside>
{% endif %}
```

---

### Taxonomy Variables

Available in taxonomy templates:

| Variable | Type | Description |
|----------|------|-------------|
| taxonomy_name | String | Taxonomy name (e.g., "tags") |
| taxonomy_term | String | Current term name |
| taxonomy_terms | Array | All terms (in taxonomy.html) |
| taxonomy_pages | Array<Page> | Pages for term |

---

## Type Reference

### Quick Reference

| Type | Description |
|------|-------------|
| String | Text value |
| String? | Optional text (may be nil) |
| Int | Integer number |
| Bool | true/false |
| Array<T> | List of type T |
| Object | Key-value map |

### Template Checking

```jinja
{# Check for nil #}
{% if page.description %}...{% endif %}

{# Check for empty array #}
{% if page.authors %}...{% endif %}

{# Check for empty string #}
{% if page.description is present %}...{% endif %}

{# Default value #}
{{ page.description | default(value=site.description) }}
```

---

## Example Templates

### page.html

```jinja
{% extends "base.html" %}

{% block content %}
<article>
  <h1>{{ page.title }}</h1>
  
  <div class="meta">
    <time>{{ page.date }}</time>
    {% if page.authors %}
    <span>by {{ page.authors | join(", ") }}</span>
    {% endif %}
    <span>{{ page.reading_time }} min read</span>
  </div>
  
  {% if page.toc %}
  <nav class="toc">{{ toc | safe }}</nav>
  {% endif %}
  
  <div class="content">
    {{ content | safe }}
  </div>
  
  {% if page.lower or page.higher %}
  <nav class="post-nav">
    {% if page.lower %}
    <a href="{{ page.lower.url }}">← {{ page.lower.title }}</a>
    {% endif %}
    {% if page.higher %}
    <a href="{{ page.higher.url }}">{{ page.higher.title }} →</a>
    {% endif %}
  </nav>
  {% endif %}
</article>
{% endblock %}
```

### section.html

```jinja
{% extends "base.html" %}

{% block content %}
<section>
  <h1>{{ section.title }}</h1>
  {% if section.description %}
  <p class="lead">{{ section.description }}</p>
  {% endif %}
  
  {{ content | safe }}
  
  <h2>Articles ({{ section.pages_count }})</h2>
  <ul class="article-list">
  {% for p in section.pages %}
    <li>
      <a href="{{ p.url }}">{{ p.title }}</a>
      {% if p.date %}<time>{{ p.date }}</time>{% endif %}
    </li>
  {% endfor %}
  </ul>
  
  {% if section.subsections %}
  <h2>Categories</h2>
  <ul>
  {% for sub in section.subsections %}
    <li>
      <a href="{{ sub.url }}">{{ sub.title }}</a>
      ({{ sub.pages_count }})
    </li>
  {% endfor %}
  </ul>
  {% endif %}
  
  {{ pagination | safe }}
</section>
{% endblock %}
```

---

## See Also

- [Template Syntax](/templates/syntax/) — Jinja2 basics
- [Functions](/templates/functions/) — Data retrieval functions
- [Filters](/templates/filters/) — Value transformation
