+++
title = "Filters"
description = "Transform values in templates with the pipe operator"
weight = 4
toc = true
+++

Filters transform values in templates. Apply with the pipe `|` operator.

Hwaro ships its own filters on top of the standard Crinja (Jinja2) built-ins (`upper`, `lower`, `join`, `map`, `select`, `batch`, and friends), so both kinds work anywhere below.

Besides the built-ins in the tables below, these Jinja2 filters are available: `abs`, `attr`, `batch`, `center`, `dictsort`, `escape` (`e`), `filesizeformat`, `float`, `format`, `groupby`, `indent`, `int`, `list`, `map`, `random`, `reject`, `rejectattr`, `round`, `select`, `selectattr`, `slice`, `string`, `striptags`, `sum`, `title`, `truncate`, `urlencode`, `urlize`, `wordcount`, `wordwrap` and `xmlattr`.

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
| regex_replace | Replace every regex match (see [Regular Expressions](#regular-expressions)) | {{ "a1b22" \| regex_replace(pattern="[0-9]+", rep="#") }} → a#b# |

## Encoding Filters

| Filter | Description | Example |
|--------|-------------|---------|
| base64_encode | Base64-encode the text (standard alphabet, padded) | {{ "hi" \| base64_encode }} → aGk= |
| base64_decode | Decode base64 (standard or URL-safe, padding optional) | {{ "aGk=" \| base64_decode }} → hi |
| md5 | MD5 digest of the text, lowercase hex | {{ "abc" \| md5 }} → 900150983cd2… |
| sha1 | SHA-1 digest, lowercase hex | {{ "abc" \| sha1 }} |
| sha256 | SHA-256 digest, lowercase hex | {{ "abc" \| sha256 }} |
| sha384 | SHA-384 digest, lowercase hex | {{ "abc" \| sha384 }} |
| sha512 | SHA-512 digest, lowercase hex | {{ "abc" \| sha512 }} |

The hash filters digest the string's UTF-8 bytes. Pass `base64=true` to get the digest in base64 instead of hex, for example `sha384-{{ css | sha384(base64=true) }}` is a Subresource Integrity value (for a file on disk, [`asset_integrity()`](/templates/functions/) does this for you). `base64_decode` stops the build with a template error when its input is not valid base64, or when the decoded bytes are not UTF-8 text.

## HTML Filters

| Filter | Description | Example |
|--------|-------------|---------|
| safe | Don't escape HTML | {{ content \| safe }} |
| strip_html | Remove HTML tags | {{ html \| strip_html }} |
| markdownify | Render Markdown | {{ text \| markdownify }} |
| xml_escape | XML escape | {{ text \| xml_escape }} |

`markdownify` follows the site's [`[markdown]`](/features/markdown-extensions/)
settings for safe mode and `smart_punctuation`, so its output matches how the
same text renders in page bodies. The rest of the extension pipeline
(footnotes, definition lists, containers, …) is not applied.

## Array Filters

| Filter | Description | Example |
|--------|-------------|---------|
| length | Get length | {{ items \| length }} |
| first | First element (empty on an empty collection) | {{ items \| first }} |
| last | Last element (empty on an empty collection) | {{ items \| last }} |
| reverse | Reverse order | {{ items \| reverse }} |
| sort | Sort array | {{ items \| sort }} |
| min | Smallest item; `attribute=` compares by a field | {{ posts \| min(attribute="date") }} |
| max | Largest item; `attribute=` compares by a field | {{ [3, 7, 5] \| max }} → 7 |
| join | Join elements | {{ tags \| join(", ") }} |
| split | Split string | {{ "a,b,c" \| split(pat=",") }} |
| where | Filter objects by field value | {{ posts \| where(attribute="draft", value=false) }} |
| sort_by | Sort objects by field | {{ posts \| sort_by(attribute="date", reverse=true) }} |
| group_by | Group objects by field | {{ posts \| group_by(attribute="section") }} |

`min` and `max` work as in Jinja2: they compare like `sort` (strings case-insensitively unless `case_sensitive=true`), `attribute=` takes a dotted path such as `"extra.weight"` and the whole item is returned, the first one wins a tie, a mapping compares its keys, and an empty list gives an undefined value.

## Collection Filters

| Filter | Description | Example |
|--------|-------------|---------|
| unique | Remove duplicates while keeping distinct value types | {{ items \| unique }} |
| flatten | Flatten nested arrays one level | {{ nested \| flatten }} |
| compact | Remove nil/empty values | {{ items \| compact }} |

## Math Filters

| Filter | Description | Example |
|--------|-------------|---------|
| ceil | Round up to integer | {{ 3.2 \| ceil }} → 4 |
| floor | Round down to integer | {{ 3.8 \| floor }} → 3 |
| num_format | Group digits in threes (see [Number Formatting](#number-formatting)) | {{ 1234567 \| num_format }} → 1,234,567 |

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
| relative_url | Prefix the path part of base_url (no scheme or host) | {{ "/img.png" \| relative_url }} |
| active_path | Is this URL the current page (or an ancestor of it)? | {{ item.url \| active_path }} |

`active_path` compares a URL (typically a [menu](/features/menus/) entry's `item.url`) against the current page. It's an exact match by default; pass `ancestor=true` to also match descendant pages:

```jinja
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
<a href="{{ item.href }}"{% if item.url | active_path(ancestor=true) %} class="open"{% endif %}>{{ item.name }}</a>
```

Both sides are normalized to one trailing slash before comparing, so `/posts` and `/posts/` are equal. The root path (`/`) only ever matches exactly, even with `ancestor=true`. An external `item.url` (`http://`, `https://`, `//`) never matches, and neither does the empty `url` of an entry written without one (a group heading).

## Data Filters

| Filter | Description | Example |
|--------|-------------|---------|
| default | Fallback for an undefined, none, or empty value (see [Default Values](#default-values)) | {{ value \| default(value="N/A") }} |
| jsonify | JSON encode | {{ data \| jsonify }} |
| tojson | JSON encode; `indent` pretty-prints with that many spaces (0–16) | {{ data \| tojson(indent=2) }} |
| date | Format date (default format `%Y-%m-%d`); `locale` translates month and weekday names (see [Date Formatting](#date-formatting)) | {{ page.date \| date(format="%B %-d", locale="ko") }} |

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

`default` returns the fallback when the value is undefined, `none`, or an empty string. The fallback keeps its type, so `default(value=0)` still works in arithmetic; a `none` fallback (`default(value=none)`) renders as an empty string. A value that is not empty is returned as follows: an array, map, or object passes through unchanged, and any other value (a string, number, or boolean) is returned as a string, so string filters such as `length` or `replace` can follow it. Pass `boolean=true` (`default(value="N/A", boolean=true)`) to also replace any falsy value: `false`, `0`, or an empty list or map.

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
- `%A` / `%a` — Weekday name / abbr (Tuesday / Tue)
- `%P` / `%p` — AM/PM / am/pm

Pass `locale` to translate the names. A template shared by several languages passes `locale=page.language`:

```jinja
{{ page.date | date(format="%B %-d일 (%a)", locale="ko") }}   {# 3월 5일 (화) #}
{{ page.date | date(format="%A %-d %B %Y", locale=page.language) }}
```

`locale` translates `%B`, `%b` (and `%h`), `%A`, `%a`, `%P`, `%p`, and the `%^` uppercase forms. Every other code, including the composite `%c` and `%r`, prints exactly as it does without a locale.

Built-in locales: `ko`, `ja`, `zh` (Simplified), `zh_TW` (Traditional; also used for `zh_Hant`, `zh_HK`, `zh_MO`), `de`, `fr`, `es`, `it`, `pt` (Brazilian, so `pt_BR` uses it), `ru`, `nl`, `pl`, `tr`, `vi`, `id`, and English. `ko`, `ko_KR`, `ko-KR` and `KO-kr` are the same locale, and a region without its own table falls back to its language (`fr_CA` uses `fr`).

Names follow CLDR's in-date ("format") forms, so Russian and Polish months are genitive (`5 марта`, `5 marca`): right next to a day number, not as a standalone month heading. An unknown locale logs one warning per build and prints English names. Without `locale`, or with an empty one, output is unchanged. `now(format=..., locale=...)` takes the same argument.

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

### Regular Expressions

`regex_replace` takes Zola's argument names, `pattern` and `rep` (or the two positionally); `rep` defaults to `""`, which deletes the matches. The pattern is PCRE2 syntax. The replacement uses the Zola and Hugo (Rust/Go regex) syntax, not Crystal's:

- `$1` or `${1}` inserts a numbered group, `$name` or `${name}` a named group (`(?<name>…)`), `$$` a literal `$`.
- `$name` takes the longest run of letters, digits and `_`, so `$1a` means a group called `1a`: write `${1}a` for group 1 followed by `a`.
- A group that doesn't exist or didn't match inserts nothing. A `$` not followed by a name stays as is, and a backslash is an ordinary character (`\1` is not a group reference).
- Empty matches follow Rust and Go too: one that starts right where the previous match ended is skipped, so `"aab" | regex_replace("a*", "-")` gives `-b-`.

```jinja
{{ "2024-03-05" | regex_replace(pattern="(\d+)-(\d+)-(\d+)", rep="$3/$2/$1") }}  {# 05/03/2024 #}
{{ "John Smith" | regex_replace(pattern="(?<first>\w+) (?<last>\w+)", rep="$last, $first") }}
{{ page.title | regex_replace("\s+", " ") }}
```

An invalid pattern, or one that backtracks past PCRE2's match limit, stops the build with a template error that names the pattern.

### Number Formatting

`num_format` groups the integer digits of a number, or of a string holding a plain decimal number, in threes. It takes three optional arguments: `decimals` (fixed decimal places, 0–20, rounded half away from zero; by default the number keeps its own decimals, and a float prints its shortest form, so `1e-7` is `0.0000001`), `separator` (default `,`) and `decimal_point` (default `.`).

```jinja
{{ 1234567 | num_format }}                                    {# 1,234,567 #}
{{ 1234.5 | num_format(decimals=2) }}                         {# 1,234.50 #}
{{ 1234567.5 | num_format(separator=".", decimal_point=",") }} {# 1.234.567,5 #}
{{ 1234567 | num_format(separator=" ") }}                     {# 1 234 567 #}
```

A value that isn't a number (text, `true`, an undefined value, NaN) comes back unchanged, so a missing front matter field doesn't break the page. Only ASCII digits count, so `"１２３"` is text. `decimals` also accepts a whole number written as a string (`decimals="2"`); any other value, such as `"x"` or `1.5`, is ignored, as if `decimals` were not given.

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
| startswith | Starts with | `{% if page.url is startswith("/blog/") %}` |
| endswith | Ends with | `{% if page.url is endswith("/") %}` |
| containing | Contains a substring (strings) or an element (lists) | `{% if page.url is containing("docs") %}` |
| matching | Regex match | `{% if asset is matching("[.](jpg\|png)$") %}` |
| empty | Is empty | `{% if page.description is empty %}` |
| present | Is not empty | `{% if page.title is present %}` |
| eq, ne, lt, le, gt, ge | Compare with a value (also `==`, `!=`, `<`, `<=`, `>`, `>=`, `equalto`, `lessthan`, `greaterthan`) | `{{ posts \| selectattr("extra.year", ">=", 2020) \| list }}` |

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
