+++
title = "Multilingual"
weight = 5
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
| default_language | string | "en" | Default language code |
| language_name | string | — | Human-readable language name |
| weight | int | 0 | Sort order (lower = first) |
| generate_feed | bool | false | Generate RSS feed for this language |
| build_search_index | bool | false | Include in search index |
| taxonomies | array | [] | Taxonomies for this language |

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

### Template Variables

Access translation data in templates:

```jinja
{% if page.translations %}
<nav class="language-switcher">
  {% for t in page.translations %}
    {% if t.is_current %}
      <span class="active">{{ t.code | upper }}</span>
    {% else %}
      <a href="{{ t.url }}">{{ t.code | upper }}</a>
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
```

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
      <a href="{{ t.url }}"{% if t.is_current %} class="current"{% endif %}>
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
        <a href="{{ t.url }}">{{ t.code }}</a>
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

## See Also

- [Configuration](/start/config/) — Full configuration reference
- [SEO](/features/seo/) — SEO features including canonical and hreflang
- [Data Model](/templates/data-model/) — Translation link properties