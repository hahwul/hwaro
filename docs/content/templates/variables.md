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

| Flat Variable | Object Access | Description |
|---------------|---------------|-------------|
| `page_title` | `page.title` | Page title |
| `page_description` | `page.description` | Page description (fallback: site description) |
| `page_url` | `page.url` | Page URL path (e.g., `/about/`) |
| `page_section` | `page.section` | Section name (e.g., `blog`) |
| `page_date` | `page.date` | Page date (YYYY-MM-DD) |
| `page_image` | `page.image` | Featured image |
| `page_language` | `page.language` | Page language code |
| `page_translations` | `page.translations` | Language variants (array) |
| `content` | — | Rendered HTML content |

### Page Object Properties

The `page` object also provides access to boolean and computed properties:

| Property | Description |
|----------|-------------|
| `page.draft` | Is draft |
| `page.toc` | Show TOC |
| `page.is_index` | Is index page |
| `page.render` | Should render |
| `page.generated` | Is generated |
| `page.in_sitemap` | Include in sitemap |

## Section Variables

For section templates:

| Flat Variable | Object Access | Description |
|---------------|---------------|-------------|
| `section_title` | `section.title` | Section title |
| `section_description` | `section.description` | Section description |
| `section_list` | `section.list` | HTML list of pages in section |
| — | `section.pages` | Array of page objects for iteration |
| — | `section.pages_count` | Count of pages |
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
  </li>
{% endfor %}
</ul>
```

Each page in `section.pages` has these properties:
- `title`, `description`, `url`, `date`, `image`
- `draft`, `toc`, `render`, `is_index`, `generated`, `in_sitemap`, `language`

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
