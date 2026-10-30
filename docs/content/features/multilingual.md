+++
title = "Multilingual"
description = "Build multilingual sites with translation linking and hreflang tags"
weight = 22
toc = true
+++

Hwaro supports building multilingual sites with automatic translation linking, language-specific URLs, and hreflang tags for SEO.

## Configuration

Enable multilingual support in `config.toml`:

```toml
default_language = "en"

[languages.en]
language_name = "English"
weight = 1

[languages.ko]
language_name = "한국어"
weight = 2
generate_feed = true
build_search_index = true
taxonomies = ["tags", "categories"]

[languages.ja]
language_name = "日本語"
weight = 3
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| default_language | string | "en" | Default language code (a blank value warns and keeps `"en"`) |
| language_name | string | the language code | Human-readable language name |
| weight | int | 1 | Sort order (lower = first) |
| generate_feed | bool | true | Generate the RSS/Atom/JSON feed for this language |
| build_search_index | bool | true | Include in search index |
| taxonomies | array | every `[[taxonomies]]` name | Taxonomies for this language; omit to inherit the global set, `[]` for none |

## Content Structure

Create translations by adding a language suffix to filenames:

```
content/
├── posts/
│   ├── hello.md         # Default language (en)
│   ├── hello.ko.md      # Korean translation
│   └── hello.ja.md      # Japanese translation
├── about.md             # Default language (en)
├── about.ko.md          # Korean translation
└── index.md             # Homepage (default)
```

### URL Mapping

| File | URL |
|------|-----|
| content/about.md | /about/ |
| content/about.ko.md | /ko/about/ |
| content/about.ja.md | /ja/about/ |
| content/posts/hello.md | /posts/hello/ |
| content/posts/hello.ko.md | /ko/posts/hello/ |

The default language pages are served at the root path. Non-default language pages are prefixed with the language code.

Spelling out the default language suffix is optional: `about.en.md` (with `default_language = "en"`) is the same as `about.md`. It is published at `/about/` and listed with the other default-language pages of its section.

### Section Translations

Section index files also support language suffixes:

```
content/
└── blog/
    ├── _index.md         # /blog/
    ├── _index.ko.md      # /ko/blog/
    └── post.md
```

## Translation Linking

Hwaro automatically links translated pages based on their filenames. Pages with the same base name (without the language suffix) are considered translations of each other.

For example, `hello.md`, `hello.ko.md`, and `hello.ja.md` are all linked as translations.

### Translation Keys

When the file names differ per language, set the same `translation_key` in each translation's front matter (Hugo's `translationKey`):

```
content/
├── about.md         # translation_key = "about"
└── 소개.ko.md        # translation_key = "about"
```

```toml
+++
title = "소개"
translation_key = "about"
+++
```

Pages that share a key are translations of each other: they get each other in `page.translations`, the hreflang tags and the sitemap alternates. The key replaces file-name pairing for the page that sets it, so set it on every translation of the page: `about.md` with a key and `about.ko.md` without one are not linked. Keys only pair pages inside one version of [versioned docs](/features/versioned-docs/), so `v1/` and `v2/` may reuse the same keys.

A key is a non-empty string; any other value is ignored with a warning. If two pages of the same language share a key, the one whose path sorts first (byte order) is linked and the build and `hwaro doctor` (`translation-key-collision`) warn about the other, which then has no translations.

To find pages that are not translated yet, run `hwaro doctor`: on a site with more than one language it lists, per language, every page or section missing a translation and every translation without a default-language original, using the same pairing (translation keys included). See [doctor](/start/tools/doctor/#what-it-checks).

### Template Variables

Access translation data in templates:

```jinja
{% if page.translations %}
<nav class="language-switcher">
  {% for t in page.translations %}
    {% if t.is_current %}
      <span class="active">{{ t.code | upper }}</span>
    {% else %}
      <a href="{{ base_url }}{{ t.url }}">{{ t.code | upper }}</a>
    {% endif %}
  {% endfor %}
</nav>
{% endif %}
```

### Translation Properties

| Property | Type | Description |
|----------|------|-------------|
| code | String | Language code (e.g., "en", "ko") |
| url | String | URL of the translated page |
| title | String | Title of the translated page |
| is_current | Bool | Whether this is the current page's language |
| is_default | Bool | Whether this is the default language |

## SEO Tags

### Canonical URLs

Hwaro generates canonical link tags for multilingual pages:

```jinja
<head>
  {{ canonical_tag | safe }}
</head>
```

Output:

```html
<link rel="canonical" href="https://example.com/about/">
```

### Hreflang Tags

Alternate language link tags are generated automatically for translated pages:

```jinja
<head>
  {{ hreflang_tags | safe }}
</head>
```

Output:

```html
<link rel="alternate" hreflang="en" href="https://example.com/about/">
<link rel="alternate" hreflang="ko" href="https://example.com/ko/about/">
<link rel="alternate" hreflang="ja" href="https://example.com/ja/about/">
<link rel="alternate" hreflang="x-default" href="https://example.com/about/">
```

The last tag, `x-default`, points at the default-language version: it is the fallback search engines show visitors whose language matches none of the alternates. It is left out when the page has no default-language version. `sitemap.xml` lists the same alternates, `x-default` included.

### Combined SEO Tags

Include both canonical and hreflang tags together:

```jinja
<head>
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
  {{ og_all_tags | safe }}
</head>
```

## Page Language

Access the current page's language in templates:

```jinja
<html lang="{{ page.language }}">
```

```jinja
{% if page.language == "ko" %}
<p>한국어 콘텐츠</p>
{% endif %}
```

Pass it to the `date` filter to print month and weekday names in the page's language (`5 mars 2024` on a French page, `5 марта 2024` on a Russian one). [Date Formatting](/templates/filters/#date-formatting) lists the built-in locales:

```jinja
<time>{{ page.date | date(format="%-d %B %Y", locale=page.language) }}</time>
```

## Scaffolding with Multilingual

Create a new site with multilingual support:

```bash
hwaro init mysite --include-multilingual en,ko,ja
```

This generates the configuration and sample content files for each specified language.

## Template Examples

### Language Switcher (Dropdown)

```jinja
{% if page.translations %}
<div class="lang-dropdown">
  <button>{{ page.language | upper }} ▾</button>
  <ul>
    {% for t in page.translations %}
    <li>
      <a href="{{ base_url }}{{ t.url }}"{% if t.is_current %} class="current"{% endif %}>
        {{ t.code | upper }}
      </a>
    </li>
    {% endfor %}
  </ul>
</div>
{% endif %}
```

### Language-Specific Navigation

```jinja
<nav>
  {% if page.language == "ko" %}
    <a href="/ko/">홈</a>
    <a href="/ko/blog/">블로그</a>
  {% elif page.language == "ja" %}
    <a href="/ja/">ホーム</a>
    <a href="/ja/blog/">ブログ</a>
  {% else %}
    <a href="/">Home</a>
    <a href="/blog/">Blog</a>
  {% endif %}
</nav>
```

### Base Template with i18n

```jinja
<!DOCTYPE html>
<html lang="{{ page.language | default(value='en') }}">
<head>
  <meta charset="utf-8">
  <title>{{ page.title }} - {{ site.title }}</title>
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
  {{ og_all_tags | safe }}
</head>
<body>
  {% if page.translations %}
  <nav class="i18n">
    {% for t in page.translations %}
      {% if t.is_current %}
        <strong>{{ t.code }}</strong>
      {% else %}
        <a href="{{ base_url }}{{ t.url }}">{{ t.code }}</a>
      {% endif %}
    {% endfor %}
  </nav>
  {% endif %}

  <main>
    {% block content %}{% endblock %}
  </main>
</body>
</html>
```

## i18n Translation Files

Hwaro supports translation files for UI strings (navigation labels, button text, etc.) using TOML files in the `i18n/` directory.

### File Structure

Create one TOML file per language:

```
i18n/
├── en.toml
├── ko.toml
└── ja.toml
```

### Translation File Format

```toml
# i18n/en.toml
[nav]
home = "Home"
blog = "Blog"
about = "About"

[common]
read_more = "Read more"
back = "Back"
```

```toml
# i18n/ko.toml
[nav]
home = "홈"
blog = "블로그"
about = "소개"

[common]
read_more = "더 읽기"
back = "뒤로"
```

Nested TOML sections are flattened to dot-separated keys (e.g., `nav.home`, `common.read_more`).

### Template Usage

Use the `t` filter to translate keys:

```jinja
<nav>
  <a href="/">{{ "nav.home" | t }}</a>
  <a href="/blog/">{{ "nav.blog" | t }}</a>
  <a href="/about/">{{ "nav.about" | t }}</a>
</nav>

<a href="{{ page.url }}">{{ "common.read_more" | t }}</a>
```

### Fallback Behavior

1. Look up the key in the current page's language
2. If not found, fall back to the default language (`default_language`)
3. If still not found, return the key itself (e.g., `"nav.home"`)

### Pluralization

Use the `pluralize` filter for count-dependent strings:

```jinja
{{ post_count }} {{ post_count | pluralize(singular="post", plural="posts") }}
```

## Per-Language Feeds

When the site is multilingual, Hwaro automatically generates separate RSS/Atom feeds for each language:

| Language | Feed Path | Contents |
|----------|-----------|----------|
| Default (e.g., `en`) | `/rss.xml` | Default language pages only (configurable) |
| Non-default (e.g., `ko`) | `/ko/rss.xml` | Only Korean pages |
| Non-default (e.g., `ja`) | `/ja/rss.xml` | Only Japanese pages |

By default, the main site feed (`/rss.xml`, `/atom.xml` or `/feed.json`) includes **only default language pages**. You can change this behavior with the `default_language_only` option. Each non-default language with `generate_feed = true` gets its own feed under its language prefix regardless of this setting.

### Configuration

#### Main Feed Language Control

```toml
[feeds]
enabled = true
default_language_only = true   # true (default): main feed = default language only
                               # false: main feed includes all languages
```

#### Per-Language Feed Control

```toml
[languages.ko]
language_name = "한국어"
generate_feed = true    # Generates /ko/rss.xml (default: true)

[languages.ja]
language_name = "日本語"
generate_feed = false   # No /ja/rss.xml will be generated
```

Language feeds share the same `sections`, `limit`, `truncate`, and `full_content` settings from the global `[feeds]` config:

```toml
[feeds]
enabled = true
type = "rss"           # or "atom", "json"
limit = 20
truncate = 0
full_content = true    # false = description/summary only
sections = []          # empty = all sections
default_language_only = true
```

### Feed Details

- **RSS feeds** include a `<language>` tag (e.g., `<language>ko</language>`)
- **Atom feeds** include an `xml:lang` attribute (e.g., `<feed xmlns="..." xml:lang="ko">`)
- **JSON feeds** include a top-level `"language"` field (e.g., `"language": "ko"`)
- Section feeds (`/ko/blog/rss.xml`) and taxonomy term feeds (`/ko/tags/crystal/rss.xml`) of a non-default language declare it the same way; default-language feeds declare none
- Feed title includes the language name: `"My Site (한국어)"`
- Self-referencing links point to the correct language path (e.g., `https://example.com/ko/rss.xml`)
- Draft pages and section index pages are excluded
- Language feeds require `[feeds] enabled = true`; `generate_feed = false` only opts a language out
- A language with no published pages gets no feed

### Template Links

Add language-specific feed links in your templates:

```jinja
{# Main feed (default language) #}
<link rel="alternate" type="application/rss+xml"
      href="{{ base_url }}/rss.xml"
      title="{{ site.title }}">

{# Language-specific feed #}
{% if page.language and page.language != "en" %}
<link rel="alternate" type="application/rss+xml"
      href="{{ base_url }}/{{ page.language }}/rss.xml"
      title="{{ site.title }} ({{ page.language }})">
{% endif %}
```

## See Also

- [Configuration](/start/config/) — Full configuration reference
- [SEO](/features/seo/) — SEO features including feeds, canonical and hreflang
- [Data Model](/templates/data-model/) — Translation link properties