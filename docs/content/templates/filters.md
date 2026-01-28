+++
title = "Filters & Tests"
toc = true
+++

Filters transform values, tests evaluate conditions.

## Filters

### Built-in Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `upper` | Uppercase | `{{ "hello" \| upper }}` → `HELLO` |
| `lower` | Lowercase | `{{ "HELLO" \| lower }}` → `hello` |
| `capitalize` | Capitalize first letter | `{{ "hello" \| capitalize }}` → `Hello` |
| `length` | Get length | `{{ items \| length }}` |
| `join` | Join array | `{{ tags \| join(", ") }}` |
| `first` | First element | `{{ items \| first }}` |
| `last` | Last element | `{{ items \| last }}` |
| `reverse` | Reverse array | `{{ items \| reverse }}` |
| `sort` | Sort array | `{{ items \| sort }}` |
| `replace` | Replace text | `{{ text \| replace("a", "b") }}` |

### Hwaro Custom Filters

| Filter | Description | Example |
|--------|-------------|---------|
| `safe` | Don't escape HTML | `{{ content \| safe }}` |
| `default` | Fallback value | `{{ value \| default(value="N/A") }}` |
| `trim` | Remove whitespace | `{{ text \| trim }}` |
| `split` | Split string | `{{ "a,b,c" \| split(pat=",") }}` |
| `slugify` | URL slug | `{{ "Hello World" \| slugify }}` → `hello-world` |
| `truncate_words` | Truncate by words | `{{ text \| truncate_words(20) }}` |
| `absolute_url` | Add base_url | `{{ "/about/" \| absolute_url }}` |
| `relative_url` | Prefix base_url | `{{ "/img.png" \| relative_url }}` |
| `strip_html` | Remove HTML tags | `{{ content \| strip_html }}` |
| `markdownify` | Render Markdown | `{{ text \| markdownify }}` |
| `xml_escape` | XML escape | `{{ text \| xml_escape }}` |
| `jsonify` | JSON encode | `{{ data \| jsonify }}` |
| `date` | Format date | `{{ page.date \| date("%Y-%m-%d") }}` |

## Filter Examples

### Default Value

```jinja
{{ page.description | default(value=site.description) }}
```

### Safe HTML

Always use `safe` for rendered content:

```jinja
{{ content | safe }}
{{ og_tags | safe }}
```

### String Manipulation

```jinja
{{ page.title | upper }}
{{ page.title | slugify }}
{{ long_text | truncate_words(50) }}
```

### URL Handling

```jinja
<a href="{{ page.url | absolute_url }}">Link</a>
<img src="{{ "/images/logo.png" | relative_url }}">
```

### Array Operations

```jinja
{% set tags = "a,b,c" | split(pat=",") %}
{% for tag in tags %}
  <span>{{ tag | trim }}</span>
{% endfor %}
```

### Date Formatting

```jinja
<time>{{ page.date | date("%B %d, %Y") }}</time>
```

Format codes:
- `%Y` — Year (2024)
- `%m` — Month (01-12)
- `%d` — Day (01-31)
- `%B` — Month name (January)
- `%b` — Month abbr (Jan)

## Tests

Tests evaluate conditions in `{% if %}` statements.

### Hwaro Custom Tests

| Test | Description | Example |
|------|-------------|---------|
| `startswith` | String starts with | `{% if page.url is startswith("/blog/") %}` |
| `endswith` | String ends with | `{% if page.url is endswith("/") %}` |
| `containing` | String contains | `{% if page.url is containing("docs") %}` |
| `empty` | Value is empty | `{% if page.description is empty %}` |
| `present` | Value is not empty | `{% if page.title is present %}` |

### Test Examples

```jinja
{% if page.url is startswith("/blog/") %}
  <span class="badge">Blog</span>
{% endif %}

{% if page.description is empty %}
  <meta name="description" content="{{ site.description }}">
{% else %}
  <meta name="description" content="{{ page.description }}">
{% endif %}

{% if page.title is present %}
  <h1>{{ page.title }}</h1>
{% endif %}
```

### Built-in Tests

```jinja
{% if value is defined %}
{% if value is none %}
{% if value is number %}
{% if value is string %}
{% if value is iterable %}
{% if value is even %}
{% if value is odd %}
```

## Chaining Filters

Filters can be chained:

```jinja
{{ page.title | lower | slugify }}
{{ content | strip_html | truncate_words(100) }}
{{ description | default(value="No description") | upper }}
```

## Common Patterns

### Conditional Meta Tags

```jinja
{% if page.image is present %}
<meta property="og:image" content="{{ page.image | absolute_url }}">
{% endif %}
```

### Section-Based Content

```jinja
{% if page.section is startswith("blog") %}
  <article class="blog-post">{{ content | safe }}</article>
{% elif page.section is startswith("docs") %}
  <div class="documentation">{{ content | safe }}</div>
{% else %}
  <main>{{ content | safe }}</main>
{% endif %}
```

### Safe Defaults

```jinja
<title>{{ page.title | default(value="Untitled") }} - {{ site.title }}</title>
```
