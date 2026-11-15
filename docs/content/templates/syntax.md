+++
title = "Syntax"
description = "Jinja2-compatible template syntax reference"
weight = 1
toc = true
+++

Hwaro uses Crinja, a Jinja2-compatible template engine. This page covers the essential syntax.

## Variables

Print values with double braces:

```jinja
{{ page.title | e }}
{{ site.description | e }}
{{ content }}
```

Printed values are HTML-escaped unless they are marked safe; see [HTML Escaping](#html-escaping).

Attribute, index and call access also work after a parenthesized expression, so you can read a field straight off a filter or function result:

```jinja
{{ (section.pages | first).title | e }}
{{ (get_section(path="blog").pages | map(attribute="title") | list)[0] | e }}
```

## HTML Escaping

Every value a template prints is HTML-escaped unless it is *safe*, as in Jinja2. Author text (titles, descriptions, section and taxonomy names, `extra` fields, data files, i18n strings) is escaped once wherever you print it, in element text and in attribute values alike; `| e` on it is harmless (it never escapes twice). Author HTML you mean to print as markup needs `| safe`: `{{ page.extra.banner | safe }}`.

The values hwaro renders as HTML (`content`, `toc`, `page.summary`, `og_all_tags`, the other `*_tags` variables, …, listed in [HTML values](/templates/data-model/#html-values)) are safe and print as they are.

`[templates] autoescape = false` in `config.toml` turns escaping off: every value prints as it is, exactly as in hwaro 0.x, so text from content or data needs `| e` wherever you print it: `<meta name="description" content="{{ page.description | e }}">`. A template written with `| e` on text and `| safe` on author HTML renders the same under both settings.

A template escapes when its output is HTML or XML: files ending in `.html`, `.htm`, `.xhtml`, `.xml`, `.svg`, `.rss` or `.atom` (a trailing `.jinja`, `.j2`, `.jinja2` or `.ecr` is ignored), names that carry no type (`page.j2`), built-in shortcodes, and the RSS and Atom feed templates. Text outputs never escape: `.json`, `.txt`, `.csv`, `.js`, `.mjs`, `.css`, `.md` and `.markdown` templates (so `page.json.jinja` and `feed.json.jinja`), `[[content.generate]]` specs and `body_template` files, and anything a text output includes. Where hwaro knows the type of the file it writes, that decides for the entry template, not its name: a page written to `index.html` escapes even through a `plain.txt.jinja` its front matter picks, and an `[outputs]` JSON, text or CSV file does not escape whatever its template is called. A file an HTML template includes or imports follows its own name (a `.js` partial does not escape), but what an HTML template imports from a text file (a `{% set %}` capture from `vars.txt.jinja`) reaches it as plain text and is escaped where printed; an `{% extends %}` chain follows the ENTRY template (the one the page renders with) — one escaping policy per render, as in Jinja2. Inside a template, turn escaping off or on for a region:

```jinja
{% autoescape false %}{{ legacy_html }}{% endautoescape %}
```

The block does not reach into a file it includes. Under autoescape, also:

- `a ~ b` (and `a + b` on strings) with a safe operand escapes the other one and is safe. `{{ "<p>" ~ x }}` prints `&lt;p&gt;`: build markup with a `{% set %}…{% endset %}` block or a macro, whose output is safe.
- `| e` and `| escape` leave a safe value alone, except HTML hwaro rendered (`content`, `page.summary`, the HTML values listed in the data model), which they still escape as before 1.0, so `{{ p.summary | escape }}` over `section.pages`, or `{{ p.content_html | escape }}` in an RSS or Atom template, shows the markup as text (a feed template's `p.summary` is plain text already, which `| escape` escapes once). The same holds for what you derive from it, as in 0.x: `{{ content[:300] | e }}`, `{{ p.summary | truncate(200) | escape }}`, `{{ (content ~ "…") | e }}`, and for `markdownify` and `tojson` output, so `data-x="{{ v | tojson | e }}"` still keeps its quotes inside the attribute. `| forceescape` and `| xml_escape` escape any value.
- `{{ x | tojson }}` is safe JSON with `<`, `>`, `&` and `'` written as `\u003c`-style escapes, ready for a `<script>`.

### Coming from 0.x

Everything else that changes between 0.22 and 1.0 is listed in [Upgrading to 1.0](/start/upgrading/).

Before 1.0 nothing was escaped unless a template said `| e`. To see what the default changes on your site, build it once as it is and once with escaping off, into two directories, and compare them:

```bash
hwaro build -o /tmp/site-1x
# now set `autoescape = false` under [templates] in config.toml
hwaro build -o /tmp/site-0x
diff -r /tmp/site-0x /tmp/site-1x
# then set it back to `true` (or keep `false` for the 0.x output)
```

Every difference is one of two things: text that 0.x printed unescaped (`Tom & Jerry` now prints as `Tom &amp; Jerry`, which the browser shows the same and which can no longer break out of an attribute), or author HTML that now shows as text and needs `| safe` where the template prints it. Then write the choice into `config.toml` (`autoescape = true`, or `false` to keep the 0.x output); `hwaro doctor` notes a site with its own templates that has not. `hwaro init` writes the key for new sites. One difference shows only in a text output (`page.json.jinja`, `page.txt.jinja`): `toc_obj.headers[].title`, `.id` and `.permalink` come out as fully escaped text there, so `it's` prints as `it&#39;s` (in 0.x they were escaped text too, apostrophes aside).

## Comments

```jinja
{# This is a comment #}
```

## Conditionals

```jinja
{% if page.description %}
<meta name="description" content="{{ page.description | e }}">
{% endif %}
```

With else:

```jinja
{% if page.draft %}
<span class="badge">Draft</span>
{% else %}
<span class="badge">Published</span>
{% endif %}
```

With elif:

```jinja
{% if page.section == "blog" %}
<article class="post">{{ content | safe }}</article>
{% elif page.section == "docs" %}
<div class="documentation">{{ content | safe }}</div>
{% else %}
<main>{{ content | safe }}</main>
{% endif %}
```

Inline, as an expression (the `else` part is optional and renders empty when left out):

```jinja
<a href="{{ item.url }}" class="{{ 'active' if item.url == page.url else '' }}">{{ item.name | e }}</a>
{% set label = page.title if page.title else "Untitled" %}
```

`a or b` returns `a` when it is truthy and `b` otherwise, so it works as a fallback: `{{ page.description or site.description }}`.

## Loops

```jinja
{% for p in section.pages %}
<li><a href="{{ p.url }}">{{ p.title | e }}</a></li>
{% endfor %}
```

With index:

```jinja
{% for tag in page.tags %}
{% if not loop.first %}, {% endif %}
{{ tag | e }}
{% endfor %}
```

Loop variables:

| Variable | Description |
|----------|-------------|
| loop.index | Current iteration (1-based) |
| loop.index0 | Current iteration (0-based) |
| loop.first | True on first iteration |
| loop.last | True on last iteration |
| loop.length | Total items (also in a filtered `{% for x in xs if … %}` loop) |
| loop.revindex | Iterations left, counting this one (`loop.revindex0`: not counting it) |
| loop.previtem / loop.nextitem | The previous / next item (empty at the ends) |
| loop.changed(value) | True when `value` differs from the previous call's |
| loop.cycle(a, b, …) | Cycles through the given values |
| loop.depth | Nesting depth in a `recursive` loop (1 at the top; `loop.depth0` starts at 0) |

### Slicing

Take part of a list or string with `[start:stop:step]`, as in Jinja2. Any part can be left out, negative numbers count from the end, and bounds past either end are clamped:

```jinja
{% for p in section.pages[:5] %}
<li><a href="{{ p.url }}">{{ p.title | e }}</a></li>
{% endfor %}

{{ page.title[:40] | e }}
{% for p in section.pages[::-1] %}…{% endfor %}
```

To show the first few items of a long list, slice it rather than skipping the rest with `{% if loop.index <= 5 %}`. The `if` version can walk the whole list on every page.

## Template Inheritance

### Base Template

`templates/base.html`:

```jinja
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ site.title | e }}{% endblock %}</title>
  {{ highlight_css | safe }}
</head>
<body>
  {% block content %}{% endblock %}
  {{ highlight_js | safe }}
</body>
</html>
```

### Child Template

`templates/page.html`:

```jinja
{% extends "base.html" %}

{% block title %}{{ page.title | e }} - {{ site.title | e }}{% endblock %}

{% block content %}
<article>
  <h1>{{ page.title | e }}</h1>
  {{ content | safe }}
</article>
{% endblock %}
```

## Includes

Include partial templates:

```jinja
{% include "partials/header.html" %}
<main>{{ content | safe }}</main>
{% include "partials/footer.html" %}
```

An included file escapes by its own name, not by the page's: `{% include "partials/x.txt.jinja" %}` (or a `.js`, `.css`, `.json`, `.md` or `.csv` partial) inside an HTML page prints its values unescaped, so put `| e` on author text such a partial prints into HTML.

A partial's own `{% set %}` and `{% macro %}` never reach the including template, with or without context; use `{% import %}` or `{% from %}` to share variables or macros.

## Macros

Define reusable snippets with `{% macro %}`, usually in a partial, and import them where you need them:

`templates/partials/macros.html`:

```jinja
{% macro card(p, show_date=true) %}
<a href="{{ p.url }}">{{ p.title | e }}</a>
{% if show_date and p.date %}<time>{{ p.date }}</time>{% endif %}
{% endmacro %}
```

```jinja
{% import "partials/macros.html" as m %}
{% for p in section.pages %}{{ m.card(p) }}{% endfor %}

{% from "partials/macros.html" import card %}
{{ card(page, show_date=false) }}
```

The same file can be imported more than once in one render, for example by a base layout and by the child template that extends it, or under two names. Only a real cycle (`a.html` imports `b.html`, which imports `a.html`) is an error.

An imported file's top-level `{% set %}` variables are available too: `{{ v.accent }}` after `{% import "partials/vars.html" as v %}`, or `{{ accent }}` after `{% from "partials/vars.html" import accent %}`. Names starting with `_` are not exported.

## Setting Variables

Set variables:

```jinja
{% set author = page.authors | first %}
<span>By {{ author }}</span>
```

## Filters

Transform values with the pipe operator:

```jinja
{{ page.title | upper }}
{{ content | safe }}
{{ page.date | date("%B %d, %Y") }}
{{ page.authors | join(", ") }}
```

See [Filters](/templates/filters/) for all available filters.

## Tests

Evaluate conditions:

```jinja
{% if page.url is startswith("/blog/") %}
<span>Blog post</span>
{% endif %}

{% if page.description is empty %}
<meta name="description" content="{{ site.description | e }}">
{% endif %}
```

Tests are not filters, but they are documented on the same page. See [Filters › Tests](/templates/filters/#tests).

## Whitespace Control

Trim whitespace with minus signs. A `-` next to a delimiter (`{%-`, `-%}`, `{{-`, `-}}`, `{#-`, `-#}`) removes all whitespace on that side, newlines included, as in Jinja2:

```jinja
{%- if condition -%}
trimmed
{%- endif -%}
```

## Raw Blocks

Output literal Jinja syntax:

```jinja
{% raw %}
{{ this will not be parsed }}
{% endraw %}
```

## Operators

### Comparison

| Operator | Description |
|----------|-------------|
| `==` | Equal |
| `!=` | Not equal |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less or equal |
| `>=` | Greater or equal |

### Logical

| Operator | Description |
|----------|-------------|
| `and` | Both true |
| `or` | Either true |
| `not` | Negation |

```jinja
{% if page.section == "blog" and not page.draft %}
<article>{{ content | safe }}</article>
{% endif %}
```

### Membership

```jinja
{% if "tutorial" in page.tags %}
<span class="badge">Tutorial</span>
{% endif %}
```

## Common Patterns

### Active Navigation

```jinja
<nav>
  <a href="/"{% if page.url == "/" %} class="active"{% endif %}>Home</a>
  <a href="/blog/"{% if page.section == "blog" %} class="active"{% endif %}>Blog</a>
</nav>
```

### Conditional Meta Tags

```jinja
<head>
  {% if page.description %}
  <meta name="description" content="{{ page.description | e }}">
  {% endif %}
  {{ og_all_tags | safe }}
</head>
```

### Section-Based Layout

```jinja
<body data-section="{{ page.section | e }}">
  {% if page.section == "docs" %}
  {% include "partials/sidebar.html" %}
  {% endif %}
  
  <main>{{ content | safe }}</main>
</body>
```

### Loop with Empty Check

```jinja
{% if section.pages %}
<ul>
{% for p in section.pages %}
  <li><a href="{{ p.url }}">{{ p.title | e }}</a></li>
{% endfor %}
</ul>
{% else %}
<p>No articles yet.</p>
{% endif %}
```

## Differences from Jinja2

Templates written for Jinja2 mostly work unchanged. These are the differences to know about:

- **Printed values.** Booleans and none print as `true`, `false` and `none` (Jinja2: `True`, `False`, `None`), and a mapping prints as `{'a' => 1}`. Format values yourself (`| tojson`, `| join`) rather than printing a raw list or mapping.
- **No Python methods.** `s.upper()`, `s.split(",")`, `d.items()`, `list.append(x)` are undefined; use the filters (`| upper`, `| split(pat=",")`, `| dictsort`). Iterating a mapping with two names (`{% for k, v in d %}`) gives its keys and values.
- **Not supported:** `namespace()`, `{% set a, b = ... %}`, `{% set x | filter %}...{% endset %}`, `*args` / `**kwargs` in a call, `self.<block>()`, `{%+`, chained comparisons (`a < b < c`), string repetition (`"-" * 3`), number literals in exponent form (`1e3`), the `items` filter and the `true` / `false` / `boolean` / `integer` / `float` tests. Each is a template error that names the spot, never silent output.
- **Operators.** `**` groups from the right (`2 ** 3 ** 2` is `512`; Jinja2 gives `64`), and a leading minus applies after it (`-2 ** 2` is `-4`; Jinja2 gives `4`). Use parentheses when it matters.
- **A test's argument without parentheses is one value**, as in Jinja2: `loop.index is divisibleby 3 and not loop.last` is `(loop.index is divisibleby 3) and not loop.last`. Before 1.0 the argument took the rest of the expression, so `page.url is startswith "/blog" ~ "/"` tested against `"/blog/"`; it now joins `"/"` onto the test's result, which is always true in an `{% if %}`. When `~`, `+`, `-`, `*`, `/`, `//`, `%`, a filter `|` or another `is` follows such an argument, the build warns with the template's file and line: write `startswith("/blog" ~ "/")` to test against the whole expression, or `(page.url is startswith "/blog") ~ "/"` to keep the new reading.
- **hwaro's own `default` and `unique`.** `default` also replaces `none` and an empty string, and returns a non-empty scalar as a string (see [Filters › Default Values](/templates/filters/#default-values)); `unique` compares strings case-sensitively unless `case_sensitive=false`.
- **Lenient calls.** A macro ignores extra arguments instead of failing, `attr` also reads mapping keys, and an imported macro sees the importing template's variables even without `with context`.
- Also available, as in Jinja2: the `range()`, `dict()`, `cycler()` and `joiner()` functions, the `forceescape` filter, and the `divisibleby`, `sameas`, `mapping`, `sequence`, `lower`, `upper`, `undefined` and `in` tests.

## See Also

- [Data Model](/templates/data-model/) — Available variables
- [Functions](/templates/functions/) — Built-in functions
- [Filters](/templates/filters/) — Filters and tests
