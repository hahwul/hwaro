+++
title = "Filters"
weight = 4
toc = true
+++

Filters transform values in templates. Apply with the pipe `|` operator.

## Syntax

```jinja
{{ value | filter }}
{{ value | filter(arg="value") }}
{{ value | filter1 | filter2 }}
```

## Text Filters

| Filter | Description | Example |
|--------|-------------|---------|
| upper | Uppercase | {{ "hello" \| upper }} → HELLO |
| lower | Lowercase | {{ "HELLO" \| lower }} → hello |
| capitalize | Capitalize first | {{ "hello" \| capitalize }} → Hello |
| trim | Remove whitespace | {{ "  hi  " \| trim }} → hi |
| replace | Replace text | {{ "hello" \| replace("l", "x") }} → hexxo |
| slugify | URL slug | {{ "Hello World" \| slugify }} → hello-world |
| truncate_words | Limit words | {{ text \| truncate_words(20) }} |

## HTML Filters

| Filter | Description | Example |
|--------|-------------|---------|
| safe | Don't escape HTML | {{ content \| safe }} |
| strip_html | Remove HTML tags | {{ html \| strip_html }} |
| markdownify | Render Markdown | {{ text \| markdownify }} |
| xml_escape | XML escape | {{ text \| xml_escape }} |

## Array Filters

| Filter | Description | Example |
|--------|-------------|---------|
| length | Get length | {{ items \| length }} |
| first | First element | {{ items \| first }} |
| last | Last element | {{ items \| last }} |
| reverse | Reverse order | {{ items \| reverse }} |
| sort | Sort array | {{ items \| sort }} |
| join | Join elements | {{ tags \| join(", ") }} |
| split | Split string | {{ "a,b,c" \| split(pat=",") }} |

## URL Filters

| Filter | Description | Example |
|--------|-------------|---------|
| absolute_url | Full URL with base | {{ "/about/" \| absolute_url }} |
| relative_url | Prefix base_url | {{ "/img.png" \| relative_url }} |

## Data Filters

| Filter | Description | Example |
|--------|-------------|---------|
| default | Fallback value | {{ value \| default(value="N/A") }} |
| jsonify | JSON encode | {{ data \| jsonify }} |
| date | Format date | {{ page.date \| date("%Y-%m-%d") }} |

## Examples

### Safe HTML

Always use `safe` for rendered content:

```jinja
{{ content | safe }}
{{ og_tags | safe }}
{{ toc | safe }}
```

### Default Values

```jinja
{{ page.description | default(value=site.description) }}
{{ page.image | default(value="/images/default.png") }}
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

### URL Handling

```jinja
<a href="{{ page.url | absolute_url }}">Permalink</a>
<img src="{{ "/logo.png" | relative_url }}">
```

### String Processing

```jinja
{{ page.title | upper }}
{{ page.title | slugify }}
{{ long_text | truncate_words(50) }}
```

### Array Operations

```jinja
{% set tags = "a,b,c" | split(pat=",") %}
{% for tag in tags %}
  <span>{{ tag | trim }}</span>
{% endfor %}

{{ page.authors | join(" & ") }}
```

### Chaining

```jinja
{{ page.title | lower | slugify }}
{{ content | strip_html | truncate_words(100) }}
{{ description | default(value="No description") | upper }}
```

---

## Tests

Tests evaluate conditions in `{% if %}` statements.

| Test | Description | Example |
|------|-------------|---------|
| startswith | Starts with | {% if page.url is startswith("/blog/") %} |
| endswith | Ends with | {% if page.url is endswith("/") %} |
| containing | Contains | {% if page.url is containing("docs") %} |
| empty | Is empty | {% if page.description is empty %} |
| present | Is not empty | {% if page.title is present %} |

### Test Examples

```jinja
{% if page.url is startswith("/blog/") %}
<span class="badge">Blog</span>
{% endif %}

{% if page.description is empty %}
<meta name="description" content="{{ site.description }}">
{% endif %}

{% if page.image is present %}
<meta property="og:image" content="{{ page.image | absolute_url }}">
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

---

## See Also

- [Data Model](/templates/data-model/) — Available variables
- [Functions](/templates/functions/) — Template functions
- [Syntax](/templates/syntax/) — Template basics
