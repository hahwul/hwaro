+++
title = "Templates"
description = "Learn how to customize your site's appearance with Jinja2 templates"
toc = true
+++

Hwaro uses Crinja (Jinja2-compatible) templates for rendering pages. Templates give you complete control over your site's HTML structure and design.

## Template Directory

All templates are stored in the `templates/` directory:

```
templates/
├── base.html           # Base template with common structure
├── page.html           # Regular page template
├── section.html        # Section index template
├── index.html          # Homepage template (optional)
├── taxonomy.html       # Taxonomy listing template
├── taxonomy_term.html  # Individual taxonomy term template
├── 404.html            # 404 error page template
├── partials/           # Partial templates
│   ├── nav.html
│   └── footer.html
└── shortcodes/         # Shortcode templates
    └── alert.html
```

## Template Types

### Base Template (`base.html`)

The base template provides the common HTML structure that other templates extend:

```jinja
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}{{ site_title }}{% endblock %}</title>
  <meta name="description" content="{{ page_description }}">
  {{ og_all_tags }}
  {{ highlight_css }}
  {{ auto_includes_css }}
</head>
<body>
  {% include "partials/nav.html" %}
  
  <main>
    {% block content %}{% endblock %}
  </main>
  
  {% include "partials/footer.html" %}
  {{ highlight_js }}
  {{ auto_includes_js }}
</body>
</html>
```

### Page Template (`page.html`)

Used for regular content pages:

```jinja
{% extends "base.html" %}

{% block title %}{{ page_title }} - {{ site_title }}{% endblock %}

{% block content %}
<article>
  <header>
    <h1>{{ page_title }}</h1>
    {% if page_date %}
    <time>{{ page_date }}</time>
    {% endif %}
  </header>
  
  <div class="content">
    {{ content }}
  </div>
</article>
{% endblock %}
```

### Section Template (`section.html`)

Used for section index pages (content directories with `_index.md` or `index.md`):

```jinja
{% extends "base.html" %}

{% block title %}{{ section_title }} - {{ site_title }}{% endblock %}

{% block content %}
<header class="section-header">
  <h1>{{ section_title }}</h1>
  {% if section_description %}
  <p>{{ section_description }}</p>
  {% endif %}
</header>

{% if content %}
<div class="section-content">
  {{ content }}
</div>
{% endif %}

<ul class="post-list">
  {{ section_list }}
</ul>
{% endblock %}
```

### Index Template (`index.html`)

Optional template for the homepage. If not present, `page.html` is used:

```jinja
{% extends "base.html" %}

{% block content %}
<div class="hero">
  <h1>Welcome to {{ site_title }}</h1>
  <p>{{ site_description }}</p>
</div>

<div class="intro">
  {{ content }}
</div>
{% endblock %}
```

## Jinja2 Syntax

Hwaro uses Crinja, a Jinja2-compatible template engine. Here's the essential syntax:

### Output Expression

Output the result of an expression:

```jinja
{{ page_title }}
{{ site_title }}
{{ page_description | default(value="No description") }}
```

### Control Structures

#### Conditionals

```jinja
{% if page_title %}
  <h1>{{ page_title }}</h1>
{% endif %}

{% if page_section == "blog" %}
  <span class="badge">Blog Post</span>
{% elif page_section == "docs" %}
  <span class="badge">Documentation</span>
{% else %}
  <span class="badge">Page</span>
{% endif %}
```

#### Loops

```jinja
{% for item in items %}
  <li>{{ item.title }}</li>
{% endfor %}
```

### Comments

```jinja
{# This is a comment and won't appear in the output #}
```

### Template Inheritance

#### Extending Templates

```jinja
{% extends "base.html" %}

{% block content %}
  <p>This replaces the content block in base.html</p>
{% endblock %}
```

#### Defining Blocks

```jinja
{% block title %}{{ site_title }}{% endblock %}
{% block content %}Default content{% endblock %}
```

### Including Partials

```jinja
{% include "partials/nav.html" %}
{% include "partials/footer.html" %}
```

### Filters

Apply transformations to values:

```jinja
{{ text | upper }}
{{ text | lower }}
{{ text | truncate_words(50) }}
{{ url | absolute_url }}
{{ content | safe }}
```

## Available Variables

### Site Variables

- `site_title` (String): Site title from config
- `site_description` (String): Site description from config
- `base_url` (String): Base URL from config

Site object access:
- `site.title`, `site.description`, `site.base_url`

### Page Variables

- `page_title` (String): Current page title
- `page_description` (String): Page description (falls back to site description)
- `page_url` (String): Current page URL path
- `page_section` (String): Section the page belongs to
- `page_date` (String): Page date in YYYY-MM-DD format
- `page_image` (String): Page image (for social sharing)
- `content` (String): Rendered page content

Page object (for boolean properties):
- `page.title`, `page.url`, `page.section`
- `page.draft` - Is draft (boolean)
- `page.toc` - Show TOC (boolean)
- `page.is_index`, `page.render`, `page.generated`, `page.in_sitemap`

### Section Variables

- `section_title` (String): Section title
- `section_description` (String): Section description
- `section_list` (String): HTML list of pages in the section

### Taxonomy Variables

- `taxonomy_name` (String): Name of the taxonomy (e.g., "tags")
- `taxonomy_term` (String): Current taxonomy term

### SEO Variables

- `og_tags` (String): OpenGraph meta tags
- `twitter_tags` (String): Twitter Card meta tags
- `og_all_tags` (String): Both OG and Twitter tags combined

### Asset Variables

- `highlight_css` (String): Syntax highlighting CSS link tag
- `highlight_js` (String): Syntax highlighting JS script tag
- `highlight_tags` (String): Both CSS and JS tags combined
- `auto_includes_css` (String): Auto-included CSS files
- `auto_includes_js` (String): Auto-included JS files
- `auto_includes` (String): All auto-included files

### Time Variables

- `current_year` (Integer): Current year (e.g., 2025)
- `current_date` (String): Current date in YYYY-MM-DD format
- `current_datetime` (String): Current datetime in YYYY-MM-DD HH:MM:SS format

### Table of Contents

- `toc` (String): Generated table of contents HTML

## Custom Filters

Hwaro provides additional filters beyond standard Jinja2:

- `{{ text | slugify }}` - Convert to URL slug
- `{{ text | truncate_words(50) }}` - Truncate by word count
- `{{ url | absolute_url }}` - Make URL absolute with base_url
- `{{ url | relative_url }}` - Prefix with base_url
- `{{ html | strip_html }}` - Remove HTML tags
- `{{ text | markdownify }}` - Render markdown to HTML
- `{{ text | xml_escape }}` - XML escape special characters
- `{{ data | jsonify }}` - JSON encode
- `{{ date | date("%Y-%m-%d") }}` - Format date
- `{{ text | split(pat=",") }}` - Split string by separator
- `{{ html | safe }}` - Mark content as safe (no escaping)
- `{{ text | trim }}` - Remove leading/trailing whitespace
- `{{ value | default(value="fallback") }}` - Provide default value if empty

## Custom Tests

Use these in conditionals:

```jinja
{% if page_url is startswith("/blog/") %}
  {# URL starts with /blog/ #}
{% endif %}

{% if page_title is endswith("!") %}
  {# Title ends with exclamation mark #}
{% endif %}

{% if page_url is containing("products") %}
  {# URL contains "products" #}
{% endif %}

{% if page_description is empty %}
  {# Description is empty #}
{% endif %}

{% if page_title is present %}
  {# Title is not empty #}
{% endif %}
```

## Custom Layouts

You can create custom layouts by setting the `layout` front matter:

```markdown
+++
title = "Landing Page"
layout = "landing"
+++

Welcome to our landing page!
```

Create the corresponding template `templates/landing.html`:

```jinja
<!DOCTYPE html>
<html lang="en">
<head>
  <title>{{ page_title }}</title>
  <style>
    /* Landing page specific styles */
  </style>
</head>
<body class="landing">
  <main>
    {{ content }}
  </main>
</body>
</html>
```

## Navigation Menus

Build navigation with active state highlighting:

```jinja
<nav>
  <a href="{{ base_url }}/"{% if page_url == "/" %} class="active"{% endif %}>Home</a>
  <a href="{{ base_url }}/blog/"{% if page_section == "blog" %} class="active"{% endif %}>Blog</a>
  <a href="{{ base_url }}/about/"{% if page_url == "/about/" %} class="active"{% endif %}>About</a>
</nav>
```

## Styling Templates

### Inline Styles

Include CSS directly in your base template:

```jinja
<style>
  :root {
    --primary: #e53935;
    --text: #f5f5f5;
    --bg: #0a0a0a;
  }
  body {
    font-family: system-ui, sans-serif;
    color: var(--text);
    background: var(--bg);
  }
</style>
```

### External Stylesheets

Reference CSS files from the `static/` directory:

```jinja
<link rel="stylesheet" href="{{ base_url }}/css/main.css">
```

### Auto Includes

Let Hwaro automatically include CSS/JS files:

1. Configure in `config.toml`:

```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]
```

2. Place files in `static/assets/`:

```
static/
└── assets/
    ├── css/
    │   ├── 01-reset.css
    │   ├── 02-typography.css
    │   └── 03-layout.css
    └── js/
        └── app.js
```

3. Use in your template:

```jinja
{{ auto_includes_css }}  {# In <head> #}
{{ auto_includes_js }}   {# Before </body> #}
```

## Best Practices

### Use Template Inheritance

Create a base template and extend it:

```jinja
{# base.html #}
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ site_title }}{% endblock %}</title>
</head>
<body>
  {% block content %}{% endblock %}
</body>
</html>
```

```jinja
{# page.html #}
{% extends "base.html" %}
{% block title %}{{ page_title }} - {{ site_title }}{% endblock %}
{% block content %}
<article>{{ content }}</article>
{% endblock %}
```

### Use Partials for Reusable Components

```jinja
{# partials/nav.html #}
<nav class="main-nav">
  <a href="{{ base_url }}/">Home</a>
  <a href="{{ base_url }}/about/">About</a>
</nav>
```

Then include it:

```jinja
{% include "partials/nav.html" %}
```

### Handle Missing Values

Use the `default` filter or conditionals:

```jinja
{{ page_description | default(value=site_description) }}

{% if page_image %}
<meta property="og:image" content="{{ page_image }}">
{% endif %}
```

### Semantic HTML

Use semantic elements for better accessibility:

```jinja
<header>...</header>
<nav>...</nav>
<main>
  <article>...</article>
  <aside>...</aside>
</main>
<footer>...</footer>
```

### Mobile-First Design

Design for mobile first, then add complexity for larger screens:

```css
/* Base styles (mobile) */
.sidebar { display: none; }

/* Desktop */
@media (min-width: 769px) {
  .sidebar { display: block; }
}
```

## Next Steps

- Learn about [Shortcodes](/guide/shortcodes/) for reusable components
- Explore [Content Management](/guide/content-management/) for organizing content
- See [SEO](/guide/seo/) for search engine optimization