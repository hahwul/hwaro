+++
title = "Filters"
description = "Transform values in templates with the pipe operator"
weight = 4
toc = true
+++

Filters transform values in templates. Apply with the pipe `|` operator.

Hwaro ships its own filters on top of the standard Crinja (Jinja2) built-ins — `upper`, `lower`, `join`, `map`, `select`, `batch`, and friends — so both kinds work anywhere below.

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
| truncate_words | Limit words; `end` sets the suffix (default `...`) | {{ text \| truncate_words(20, end="…") }} |

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
| where | Filter objects by field value | {{ posts \| where(attribute="draft", value=false) }} |
| sort_by | Sort objects by field | {{ posts \| sort_by(attribute="date", reverse=true) }} |
| group_by | Group objects by field | {{ posts \| group_by(attribute="section") }} |

## Collection Filters

| Filter | Description | Example |
|--------|-------------|---------|
| unique | Remove duplicates | {{ items \| unique }} |
| flatten | Flatten nested arrays | {{ nested \| flatten }} |
| compact | Remove nil/empty values | {{ items \| compact }} |

## Math Filters

| Filter | Description | Example |
|--------|-------------|---------|
| ceil | Round up to integer | {{ 3.2 \| ceil }} → 4 |
| floor | Round down to integer | {{ 3.8 \| floor }} → 3 |

## i18n Filters

| Filter | Description | Example |
|--------|-------------|---------|
| t | Translate a key | {{ "nav.home" \| t }} |
| pluralize | Select singular/plural form | {{ count \| pluralize(singular="item", plural="items") }} |

The `t` filter looks up translation keys from TOML files in the `i18n/` directory. It uses the current page's language and falls back to the default language, then returns the key itself if no translation is found. See [Multilingual](/features/multilingual/) for i18n file setup.

## Debug Filters

| Filter | Description | Example |
|--------|-------------|---------|
| inspect | Debug representation | {{ value \| inspect }} |

## URL Filters

| Filter | Description | Example |
|--------|-------------|---------|
| absolute_url | Full URL with base | {{ "/about/" \| absolute_url }} |
| relative_url | Prefix base_url | {{ "/img.png" \| relative_url }} |
| active_path | Is this URL the current page (or an ancestor of it)? | {{ item.url \| active_path }} |

`active_path` compares a URL (typically a [menu](/features/menus/) entry's `item.url`) against the current page. It's an exact match by default; pass `ancestor=true` to also match descendant pages:

```jinja
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
<a href="{{ item.href }}"{% if item.url | active_path(ancestor=true) %} class="open"{% endif %}>{{ item.name }}</a>
```

Both sides are normalized to one trailing slash before comparing, so `/posts` and `/posts/` are equal. The root path (`/`) only ever matches exactly, even with `ancestor=true`. An external `item.url` (`http://`, `https://`, `//`) never matches.

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

### Strings and Chaining

```jinja
{{ page.title | lower | slugify }}
{{ content | strip_html | truncate_words(100) }}
{{ description | default(value="No description") | upper }}

{% set tags = "a,b,c" | split(pat=",") %}
{% for tag in tags %}
  <span>{{ tag | trim }}</span>
{% endfor %}
```

### Collection Querying

```jinja
{% set published = site.pages | where(attribute="draft", value=false) %}
{% set newest = published | sort_by(attribute="date", reverse=true) %}

{% for group in newest | group_by(attribute="section") %}
  <h3>{{ group.grouper }}</h3>
  <ul>
  {% for p in group.list %}
    <li><a href="{{ p.url }}">{{ p.title }}</a></li>
  {% endfor %}
  </ul>
{% endfor %}

{# Unique tags across all pages #}
{% set all_tags = site.pages | map(attribute="tags") | flatten | unique %}
```

### Translations

```jinja
{# Translate UI strings (requires i18n/*.toml files) #}
<nav>
  <a href="/">{{ "nav.home" | t }}</a>
  <a href="/blog/">{{ "nav.blog" | t }}</a>
</nav>

{# Pluralize based on count #}
<p>{{ post_count }} {{ post_count | pluralize(singular="post", plural="posts") }}</p>
```

---

## Tests

Tests evaluate conditions in `{% if %}` statements.

| Test | Description | Example |
|------|-------------|---------|
| startswith | Starts with | {% if page.url is startswith("/blog/") %} |
| endswith | Ends with | {% if page.url is endswith("/") %} |
| containing | Contains | {% if page.url is containing("docs") %} |
| matching | Regex match | {% if asset is matching("[.](jpg|png)$") %} |
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

{% if "hero.jpg" is matching("[.](jpg|png)$") %}
<span>Image file</span>
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
