+++
title = "Variables"
toc = true
+++

Variables available in Jinja2 templates.

## Site Variables

From `config.toml`:

| Variable | Description |
|----------|-------------|
| `site_title` | Site title |
| `site_description` | Site description |
| `base_url` | Base URL (no trailing slash) |

Object access: `site.title`, `site.description`, `site.base_url`

## Page Variables

From front matter and content:

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
| `content` | Rendered HTML content |

### Page Object

Access boolean properties via `page` object:

| Property | Description |
|----------|-------------|
| `page.draft` | Is draft |
| `page.toc` | Show TOC |
| `page.is_index` | Is index page |
| `page.render` | Should render |
| `page.generated` | Is generated |
| `page.in_sitemap` | Include in sitemap |
| `page.language` | Page language code |
| `page.translations` | Language variants (array) |

## Section Variables

For section templates:

| Variable | Description |
|----------|-------------|
| `section_title` | Section title |
| `section_description` | Section description |
| `section_list` | HTML list of pages in section |

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

## Table of Contents

| Variable | Description |
|----------|-------------|
| `toc` | Generated TOC HTML |

Only populated when `toc = true` in front matter.

## Usage Examples

### Page Title

```jinja
<title>{{ page_title }} - {{ site_title }}</title>
```

### Meta Tags

```jinja
<head>
  <meta name="description" content="{{ page_description }}">
  {{ og_all_tags }}
  {{ highlight_css }}
  {{ auto_includes_css }}
</head>
```

### Conditional Content

```jinja
{% if page_description %}
<p class="lead">{{ page_description }}</p>
{% endif %}

{% if page.toc %}
<aside>{{ toc }}</aside>
{% endif %}
```

### Active Navigation

```jinja
<nav>
  <a href="/"{% if page_url == "/" %} class="active"{% endif %}>Home</a>
  <a href="/blog/"{% if page_section == "blog" %} class="active"{% endif %}>Blog</a>
</nav>
```

### Section-Based Styling

```jinja
<body data-section="{{ page_section }}">
```

### Canonical URL

```jinja
<link rel="canonical" href="{{ base_url }}{{ page_url }}">
```

### RSS Link

```jinja
<link rel="alternate" type="application/rss+xml" href="{{ base_url }}/rss.xml">
```

### Footer Year

```jinja
<footer>
  <p>&copy; {{ current_year }} {{ site_title }}</p>
</footer>
```
