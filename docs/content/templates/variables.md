+++
title = "Variables"
toc = true
+++

Variables available in Jinja2 templates.

## Site Variables

From `config.toml`:

| Flat Variable | Object Access | Description |
|---------------|---------------|-------------|
| `site_title` | `site.title` | Site title |
| `site_description` | `site.description` | Site description |
| `base_url` | `site.base_url` | Base URL (no trailing slash) |

## Page Variables

From front matter and content:

### Flat Variables

| Variable | Description |
|----------|-------------|
| `page_title` | Page title |
| `page_description` | Page description (fallback: site description) |
| `page_url` | Page URL path (e.g., `/about/`) |
| `page_section` | Section name (e.g., `blog`) |
| `page_date` | Page date (YYYY-MM-DD) |
| `page_image` | Featured image |
| `page_language` | Page language code |
| `page_translations` | Language variants (array) |
| `page_summary` | Content summary |
| `page_word_count` | Word count |
| `page_reading_time` | Reading time (minutes) |
| `page_permalink` | Absolute URL with base_url |
| `page_authors` | Authors array |
| `page_weight` | Sort weight |
| `content` | Rendered HTML content |

### Page Object Properties

The `page` object provides access to all properties:

| Property | Type | Description |
|----------|------|-------------|
| `page.title` | string | Page title |
| `page.description` | string | Page description |
| `page.url` | string | Relative URL path |
| `page.permalink` | string | Absolute URL with base_url |
| `page.section` | string | Section name |
| `page.date` | string | Publication date (YYYY-MM-DD) |
| `page.updated` | string | Last updated date |
| `page.image` | string | Featured image |
| `page.draft` | bool | Is draft |
| `page.toc` | bool | Show TOC |
| `page.render` | bool | Should render |
| `page.is_index` | bool | Is index page |
| `page.generated` | bool | Is generated |
| `page.in_sitemap` | bool | Include in sitemap |
| `page.in_search_index` | bool | Include in search |
| `page.language` | string | Language code |
| `page.translations` | array | Language variants |
| `page.weight` | int | Sort weight |
| `page.word_count` | int | Word count |
| `page.reading_time` | int | Reading time (minutes) |
| `page.summary` | string | Content summary |
| `page.authors` | array | Author names |
| `page.extra` | object | Custom metadata |
| `page.lower` | object | Previous page |
| `page.higher` | object | Next page |
| `page.ancestors` | array | Parent sections |

### Page Navigation (lower/higher)

Navigate between pages in the same section:

```jinja
{% if page.lower %}
<a href="{{ page.lower.url }}">← {{ page.lower.title }}</a>
{% endif %}

{% if page.higher %}
<a href="{{ page.higher.url }}">{{ page.higher.title }} →</a>
{% endif %}
```

Lower/higher objects have: `title`, `url`, `description`, `date`

### Ancestors

Build breadcrumb navigation:

```jinja
<nav class="breadcrumbs">
  <a href="/">Home</a>
  {% for ancestor in page.ancestors %}
  / <a href="{{ ancestor.url }}">{{ ancestor.title }}</a>
  {% endfor %}
  / <span>{{ page.title }}</span>
</nav>
```

### Extra Fields

Access custom front matter fields:

```jinja
{% if page.extra.featured %}
<span class="badge">Featured</span>
{% endif %}

<div class="rating">{{ page.extra.rating }} / 5</div>
```

## Section Variables

For section templates:

| Flat Variable | Object Access | Description |
|---------------|---------------|-------------|
| `section_title` | `section.title` | Section title |
| `section_description` | `section.description` | Section description |
| `section_list` | `section.list` | HTML list of pages in section |
| — | `section.pages` | Array of page objects for iteration |
| — | `section.pages_count` | Count of pages |
| — | `section.subsections` | Child sections array |
| — | `section.assets` | Static files in section |
| — | `section.page_template` | Default page template |
| — | `section.paginate_path` | Pagination URL pattern |
| — | `section.redirect_to` | Redirect URL |
| `pagination` | — | Pagination navigation HTML |

### Using section.pages

For more control over section listing, iterate over `section.pages`:

```jinja
<ul>
{% for p in section.pages %}
  <li>
    <a href="{{ p.url }}">{{ p.title }}</a>
    {% if p.description %}
    <p>{{ p.description }}</p>
    {% endif %}
    {% if p.reading_time %}
    <span>{{ p.reading_time }} min read</span>
    {% endif %}
  </li>
{% endfor %}
</ul>
```

Each page in `section.pages` has these properties:
- `title`, `description`, `url`, `date`, `image`
- `draft`, `toc`, `render`, `is_index`, `generated`, `in_sitemap`, `language`

### Subsections

Access child sections:

```jinja
{% if section.subsections %}
<h2>Categories</h2>
<ul>
{% for sub in section.subsections %}
  <li>
    <a href="{{ sub.url }}">{{ sub.title }}</a>
    ({{ sub.pages_count }} articles)
  </li>
{% endfor %}
</ul>
{% endif %}
```

### Section Assets

List static files in the section directory:

```jinja
{% if section.assets %}
<h3>Downloads</h3>
<ul>
{% for asset in section.assets %}
  <li><a href="{{ section.url }}{{ asset }}">{{ asset }}</a></li>
{% endfor %}
</ul>
{% endif %}
```

## Table of Contents

| Variable | Description |
|----------|-------------|
| `toc` | Generated TOC HTML |
| `toc_obj.html` | Same as `toc` (structured access) |

Only populated when `toc = true` in front matter.

## Taxonomy Variables

| Variable | Description |
|----------|-------------|
| `taxonomy_name` | Taxonomy name (e.g., "tags") |
| `taxonomy_term` | Current term (e.g., "crystal") |

## SEO Variables

| Variable | Description |
|----------|-------------|
| `og_tags` | OpenGraph meta tags |
| `twitter_tags` | Twitter Card meta tags |
| `og_all_tags` | Both OG and Twitter tags |

## Asset Variables

| Variable | Description |
|----------|-------------|
| `highlight_css` | Syntax highlighting CSS |
| `highlight_js` | Syntax highlighting JS |
| `highlight_tags` | Both CSS and JS |
| `auto_includes_css` | Auto-included CSS |
| `auto_includes_js` | Auto-included JS |
| `auto_includes` | All auto-includes |

## Time Variables

| Variable | Description |
|----------|-------------|
| `current_year` | Current year (e.g., 2025) |
| `current_date` | Current date (YYYY-MM-DD) |
| `current_datetime` | Current datetime |

## Usage Examples

### Page Title (Flat vs Object)

```jinja
{# Using flat variables #}
<title>{{ page_title }} - {{ site_title }}</title>

{# Using object access #}
<title>{{ page.title }} - {{ site.title }}</title>
```

### Meta Tags

```jinja
<head>
  <meta name="description" content="{{ page.description }}">
  {{ og_all_tags }}
  {{ highlight_css }}
  {{ auto_includes_css }}
</head>
```

### Conditional Content

```jinja
{% if page.description %}
<p class="lead">{{ page.description }}</p>
{% endif %}

{% if page.toc %}
<aside>{{ toc }}</aside>
{% endif %}
```

### Active Navigation

```jinja
<nav>
  <a href="/"{% if page.url == "/" %} class="active"{% endif %}>Home</a>
  <a href="/blog/"{% if page.section == "blog" %} class="active"{% endif %}>Blog</a>
</nav>
```

### Section Listing

```jinja
{# Using section.list (pre-rendered HTML) #}
<ul>{{ section.list }}</ul>

{# Using section.pages (full control) #}
<ul>
{% for p in section.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>
```

### Section-Based Styling

```jinja
<body data-section="{{ page.section }}">
```

### Canonical URL

```jinja
<link rel="canonical" href="{{ page.permalink }}">
{# Or manually: #}
<link rel="canonical" href="{{ base_url }}{{ page.url }}">
```

### RSS Link

```jinja
<link rel="alternate" type="application/rss+xml" href="{{ base_url }}/rss.xml">
```

### Footer Year

```jinja
<footer>
  <p>&copy; {{ current_year }} {{ site.title }}</p>
</footer>
```

### Word Count and Reading Time

```jinja
<div class="meta">
  {{ page.word_count }} words · {{ page.reading_time }} min read
</div>
```

### Authors

```jinja
{% if page.authors %}
<div class="authors">
  By: {{ page.authors | join(", ") }}
</div>
{% endif %}
```

### Previous/Next Navigation

```jinja
<nav class="post-nav">
  {% if page.lower %}
  <a href="{{ page.lower.url }}" class="prev">
    ← {{ page.lower.title }}
  </a>
  {% endif %}
  
  {% if page.higher %}
  <a href="{{ page.higher.url }}" class="next">
    {{ page.higher.title }} →
  </a>
  {% endif %}
</nav>
```

### Multilingual Links

For multilingual sites, use `page.translations` to create language switchers:

```jinja
{# Language switcher #}
{% if page.translations %}
<nav class="language-switcher">
  {% for translation in page.translations %}
    {% if translation.is_current %}
      <span class="current">{{ translation.code|upper }}</span>
    {% else %}
      <a href="{{ translation.url }}" title="{{ translation.title }}">{{ translation.code|upper }}</a>
    {% endif %}
  {% endfor %}
</nav>
{% endif %}
```

Each translation object has:
- `code`: Language code (e.g., "en", "ko")
- `url`: Full URL to the translated page
- `title`: Page title in that language
- `is_current`: True if this is the current page's language
- `is_default`: True if this is the default language

## See Also

- [Built-in Functions](/templates/built-in/)
- [Filters](/templates/filters/)
- [Pagination](/templates/pagination/)
- [Page Documentation](/content/page/)
- [Section Documentation](/content/section/)