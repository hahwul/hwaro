+++
title = "Built-in Templates"
toc = true
+++

Default templates for rendering different content types.

## Template Hierarchy

| Template | Purpose |
|----------|---------|
| `base.html` | Common HTML structure |
| `page.html` | Regular pages |
| `section.html` | Section index pages |
| `index.html` | Homepage (optional) |
| `taxonomy.html` | Taxonomy listing |
| `taxonomy_term.html` | Taxonomy term page |
| `404.html` | Error page |

## base.html

Common layout inherited by other templates:

```jinja
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{% block title %}{{ site.title }}{% endblock %}</title>
  <meta name="description" content="{{ page.description }}">
  {{ og_all_tags }}
  {{ highlight_css }}
  {{ auto_includes_css }}
</head>
<body>
  {% block body %}
  <header>
    {% include "partials/nav.html" %}
  </header>
  
  <main>
    {% block content %}{% endblock %}
  </main>
  
  {% include "partials/footer.html" %}
  {% endblock %}
  
  {{ highlight_js }}
  {{ auto_includes_js }}
</body>
</html>
```

## page.html

For regular content pages:

```jinja
{% extends "base.html" %}

{% block title %}{{ page.title }} - {{ site.title }}{% endblock %}

{% block content %}
<article>
  <header>
    <h1>{{ page.title }}</h1>
    {% if page.date %}
    <time>{{ page.date }}</time>
    {% endif %}
  </header>
  
  {% if page.toc %}
  <aside class="toc">{{ toc }}</aside>
  {% endif %}
  
  <div class="content">
    {{ content }}
  </div>
</article>
{% endblock %}
```

## section.html

For section index pages (`_index.md`):

```jinja
{% extends "base.html" %}

{% block title %}{{ section.title }} - {{ site.title }}{% endblock %}

{% block content %}
<header>
  <h1>{{ section.title }}</h1>
  {% if section.description %}
  <p>{{ section.description }}</p>
  {% endif %}
</header>

{% if content %}
<div class="section-content">
  {{ content }}
</div>
{% endif %}

{# Using section.list for simple HTML output #}
<ul class="page-list">
  {{ section.list }}
</ul>

{# Or use section.pages for full control #}
{#
<ul class="page-list">
{% for p in section.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>
#}

{{ pagination }}
{% endblock %}
```

## index.html

Optional homepage template. Falls back to `page.html` if not present:

```jinja
{% extends "base.html" %}

{% block content %}
<div class="hero">
  <h1>{{ site.title }}</h1>
  <p>{{ site.description }}</p>
</div>

<div class="intro">
  {{ content }}
</div>
{% endblock %}
```

## taxonomy.html

Lists all terms in a taxonomy:

```jinja
{% extends "base.html" %}

{% block title %}{{ taxonomy_name | capitalize }} - {{ site.title }}{% endblock %}

{% block content %}
<h1>{{ taxonomy_name | capitalize }}</h1>

<ul class="taxonomy-list">
  {{ content }}
</ul>
{% endblock %}
```

## taxonomy_term.html

Lists content with a specific term:

```jinja
{% extends "base.html" %}

{% block title %}{{ taxonomy_term }} - {{ site.title }}{% endblock %}

{% block content %}
<h1>{{ taxonomy_term }}</h1>

<div class="term-pages">
  {{ content }}
</div>
{% endblock %}
```

## 404.html

Error page for missing content:

```jinja
{% extends "base.html" %}

{% block title %}Page Not Found - {{ site.title }}{% endblock %}

{% block content %}
<div class="error-page">
  <h1>404</h1>
  <p>Page not found.</p>
  <a href="{{ base_url }}/">Go home</a>
</div>
{% endblock %}
```

## Partials

Reusable template fragments in `templates/partials/`:

### partials/nav.html

```jinja
<nav class="main-nav">
  <a href="{{ base_url }}/" class="logo">{{ site.title }}</a>
  <a href="{{ base_url }}/"{% if page.url == "/" %} class="active"{% endif %}>Home</a>
  <a href="{{ base_url }}/blog/"{% if page.section == "blog" %} class="active"{% endif %}>Blog</a>
  <a href="{{ base_url }}/about/"{% if page.url == "/about/" %} class="active"{% endif %}>About</a>
</nav>
```

### partials/footer.html

```jinja
<footer>
  <p>&copy; {{ current_year }} {{ site.title }}</p>
</footer>
```

## Custom Templates

Override default template with `template` front matter:

```markdown
+++
title = "Landing Page"
template = "landing"
+++
```

Create `templates/landing.html`:

```jinja
<!DOCTYPE html>
<html>
<head>
  <title>{{ page.title }}</title>
</head>
<body class="landing">
  {{ content }}
</body>
</html>
```

## Template Resolution

1. Check `template` in front matter
2. Check for content-type specific template
3. Fall back to default template

| Content | Resolution |
|---------|------------|
| `template = "custom"` | `custom.html` |
| Homepage | `index.html` → `page.html` |
| Section index | `section.html` |
| Regular page | `page.html` |
