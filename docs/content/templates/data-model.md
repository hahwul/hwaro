+++
title = "Data Model"
description = "Site, Section, and Page data types available in templates"
weight = 2
toc = true
+++

Hwaro's template system centers on three core types: **Site**, **Section**, and **Page**. This page is a **template-side reference** — all properties and variables you can use when building templates. For how to write content and set front matter fields, see [Writing](/writing/).

## Hierarchy

```
Site
├── Config (title, base_url, ...)
├── Pages[] (standalone pages)
├── Sections[]
│   ├── Pages[] (pages in section)
│   └── Subsections[]
│       ├── Pages[]
│       └── Subsections[] (recursive)
└── Taxonomies{}
    └── Terms{}
        └── Pages[]
```

### Relationships

- A **Site** contains multiple **Sections** and standalone **Pages**
- A **Section** contains **Pages** and child **Subsections**
- **Subsections** can nest indefinitely
- **Taxonomies** group **Pages** by terms

## Site

The root container. Configured in `config.toml`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| site.title | String | Site title |
| site.description | String | Site description |
| site.base_url | String | Base URL (no trailing slash) |
| site.pages | Array<Page> | All non-section pages |
| site.sections | Array<Section> | All section index pages |
| site.taxonomies | Object | All taxonomy groups and terms |
| site.data | Object | Data loaded from `data/` directory |
| site.authors | Object | Aggregated author data |
| site.menus | Object | Named menus for the **default language** (see [Menus](#menus)) |

### Flat Aliases

| Variable | Equivalent |
|----------|------------|
| site_title | site.title |
| site_description | site.description |
| base_url | site.base_url |

### Data Directory

Hwaro allows you to store auxiliary data in the `data/` directory. Files ending in `.yml`, `.yaml`, `.json`, or `.toml` are automatically loaded and exposed via `site.data`.

#### File Structure

```text
data/
├── authors.yml
├── products.json
├── config.toml
└── users/
    ├── alice.yml
    ├── bob.yml
    └── cho.yml
```

#### Accessing Data

Data is accessed by the filename (without extension).

For example, `data/products.json`:

```json
[
  {"name": "Widget", "price": 10},
  {"name": "Gadget", "price": 20}
]
```

Can be accessed in templates:

```jinja
{% for product in site.data.products %}
  <h2>{{ product.name }}</h2>
  <p>{{ product.price }}</p>
{% endfor %}
```

#### Subdirectories

Subdirectories under `data/` become nested maps. Each file becomes a child keyed by its filename (without extension), and the parent directory itself is iterable.

Given the layout above, `data/users/alice.yml`, `data/users/bob.yml`, and `data/users/cho.yml` are exposed as:

- `site.data.users.alice`, `site.data.users.bob`, `site.data.users.cho` — individual file contents
- `site.data.users` — a map you can iterate to list every user

```jinja
{% for name, user in site.data.users %}
  <h3>{{ name }}</h3>
  <p>{{ user.bio }}</p>
{% endfor %}
```

Directories nest arbitrarily: `data/users/admins/root.yml` → `site.data.users.admins.root`.

**Conflicts.** If a directory and a file share the same stem (e.g. `data/users.yml` alongside `data/users/`), the **directory wins** and the file is ignored. Hwaro emits a warning during the build so the shadowed file is not silently dropped.

### Remote Data Sources

`site.data` can also be fed from HTTP(S) endpoints, declared in `config.toml`. Each source is fetched **once per build, before anything renders** — templates never trigger network requests, and every endpoint the build talks to is visible in one place.

For the standalone configuration guide, including cache behavior, offline error
policies, timeouts, and security boundaries, see [Remote Data Sources](/features/remote-data/).

```toml
[[data.remote]]
key = "team"                # exposed as site.data.team
url = "https://api.example.com/team"
format = "json"             # json | toml | yaml | csv (optional, see inference below)
headers = { Authorization = "Bearer ${API_TOKEN}" }
cache = "1h"                # skip the request while the cached copy is younger than this
on_error = "fail"           # fail | warn-and-use-cache | warn-and-skip
```

Templates consume the result exactly like a local data file — `site.data.team` — so a key can move between `data/team.json` and a remote source without touching any template. To turn the records themselves into pages instead of feeding templates, see [Content Generation](/features/content-generation/).

| Field | Required | Meaning |
|-------|----------|---------|
| `key` | yes | Name under `site.data`. Letters, digits, `_`, `-` only; each key may be declared once. Keys are compared case-insensitively — `Team` and `team` would share one cache file on macOS and Windows, so they are rejected as duplicates. |
| `url` | yes | Absolute `http://` or `https://` URL. Other schemes are rejected at config load. |
| `format` | no | `json`, `toml`, `yaml`, or `csv`. When omitted, inferred from the response `Content-Type`, then from the file extension of the URL the request finally landed on (after any redirects). If neither identifies a format, the fetch fails with a hint to set `format` explicitly. |
| `headers` | no | Extra request headers. Treated as credentials: never logged, and dropped when a redirect leaves the original origin. |
| `cache` | no | Disk-cache TTL such as `"90s"`, `"30m"`, `"1h"`, `"7d"` (units combine: `"1h30m"`). While the cached copy is fresh, the build skips the request entirely. Without `cache`, every build refetches — but the last payload is still saved for `warn-and-use-cache`. |
| `on_error` | no | What to do when the fetch or parse fails. `fail` (default) aborts the build; `warn-and-use-cache` warns and builds from the last successfully fetched payload (any age); `warn-and-skip` warns and leaves `site.data.<key>` unset for this build. |

CSV payloads parse to an array of rows, each an array of stripped string cells — the same shape `load_data()` produces for `.csv` files.

**Environment variables.** `${VAR}` in `url` and `headers` values is replaced from the environment. A referenced variable that is not set fails the build with an error naming the variable (elsewhere in `config.toml` this is only a warning); write `${VAR:-default}` to provide a fallback instead. The error is raised when the source is actually fetched, so commands that never fetch — `hwaro deploy`, `hwaro new`, `hwaro tool ...` — keep working without the variable exported.

**Caching.** Payloads are cached under `.hwaro/remote_data/` — outside `data/` and every other directory `hwaro serve` watches, so serve rebuilds within the TTL reuse the cache instead of re-hitting the API, and cache writes never trigger a rebuild. The cache also survives `hwaro build --full` (only the page cache is cleared), and it is what lets an offline build succeed with `on_error = "warn-and-use-cache"`. `.hwaro/` is self-ignoring (hwaro writes `.hwaro/.gitignore` when creating it), so the cache never appears in `git status`. During a long `hwaro serve` session each source is fetched once and then reused in memory: an entry with a `cache` TTL is re-fetched on the first full rebuild after that TTL expires, and an entry without one is fetched once for the whole session rather than on every save. If a re-fetch fails while the session already holds a payload, serve warns and keeps using it — whatever `on_error` says — so an editor keeps working offline. `hwaro build` is unaffected: it is one process per build and always follows `cache`/`on_error` exactly. A changed payload invalidates cached pages the same way an edited `data/` file does.

**Timeouts.** Each source gets 10s to connect, 30s per read, and 120s overall — the last one spans every redirect hop and the whole body, so a source that trickles bytes just inside the read timeout can't stall the build. Exceeding any of them is a fetch failure, handled by `on_error` like any other.

**Collisions.** A remote `key` that also exists on disk (`data/team.json` next to `key = "team"`) is a config error naming both sources — a key must have exactly one source, so `site.data.team` never silently depends on which one wins.

Remote sources are deliberately config-only: `load_data()` and shortcodes cannot take a URL. If you need more than a GET request per source — pagination, POST bodies, reshaping — fetch with a [pre-build hook](/features/build-hooks/#fetching-data-from-an-api) into `data/` instead.

### Site Authors

Hwaro automatically aggregates all authors defined in the `authors` front matter field (`authors = ["id"]`) into `site.authors`.

#### Defining Authors

You can enrich author data by creating a `data/authors.yml` (or `.json`, `.toml`) file. Keys must match the author IDs used in the page front matter.

**content/my-post.md**

```yaml
---
title: "My Post"
authors: ["john-doe"]
---
```

**data/authors.yml**

```yaml
john-doe:
  name: "John Doe"
  bio: "Creator of things."
  avatar: "/images/john.jpg"
```

#### Usage in Templates

The `site.authors` object contains all authors found on the site. Each author object has:
- `key`: The author ID (e.g., "john-doe")
- `name`: The author name (from data or ID fallback)
- `pages`: List of pages by this author (sorted by date)
- Any custom fields from `data/authors.yml`

```jinja
{% for id, author in site.authors %}
  <div class="author">
    <img src="{{ author.avatar }}" alt="{{ author.name }}">
    <h3>{{ author.name }}</h3>
    <p>{{ author.bio }}</p>

    <h4>Recent Posts</h4>
    <ul>
    {% for p in author.pages %}
      <li><a href="{{ p.url }}">{{ p.title }}</a></li>
    {% endfor %}
    </ul>
  </div>
{% endfor %}
```

### Example

```jinja
<title>{{ site.title }}</title>
<link rel="canonical" href="{{ site.base_url }}{{ page.url }}">
```

---

## Section

A directory with `_index.md` that groups related content.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| section.title | String | Section title |
| section.description | String? | Section description |
| section.pages | Array<Page> | Pages in this section |
| section.pages_count | Int | Number of pages |
| section.list | String | Pre-rendered HTML list (`section_list`) |
| section.subsections | Array<Section> | Child sections |
| section.assets | Array<String> | Static files in section |
| section.page_template | String? | Default template for pages |
| section.paginate_path | String | Pagination URL pattern |
| section.redirect_to | String? | Redirect URL |

For the current section URL in `section.html`, use `page.url`.

### Flat Aliases

| Variable | Equivalent |
|----------|------------|
| section_title | section.title |
| section_description | section.description |
| section_list | Pre-rendered HTML list of pages |

### From Front Matter

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| sort_by | String? | "date" | Sort by: date (newest first), weight (lowest first), title (A→Z) |
| reverse | Bool? | false | Flip the natural sort order — see [Writing › Sections › Sort direction](/writing/sections/#sort-direction) |
| paginate | Int? | — | Pages per page |
| transparent | Bool | false | Pass pages to parent |
| generate_feeds | Bool | false | Generate RSS feed |

### Iterating Pages

```jinja
{% for p in section.pages %}
<article>
  <h2><a href="{{ p.url }}">{{ p.title }}</a></h2>
  <time>{{ p.date }}</time>
  {% if p.description %}
  <p>{{ p.description }}</p>
  {% endif %}
</article>
{% endfor %}
```

### Iterating Subsections

```jinja
{% for sub in section.subsections %}
<div class="category">
  <a href="{{ sub.url }}">{{ sub.title }}</a>
  <span>({{ sub.pages_count }} articles)</span>
</div>
{% endfor %}
```

### Using section_list

For simple listings, use the pre-rendered HTML:

```jinja
<ul>{{ section_list | safe }}</ul>
```

For custom markup, iterate `section.pages` directly:

```jinja
<ul>
{% for p in section.pages %}
  <li>
    <a href="{{ p.url }}">{{ p.title }}</a>
    {% if p.date %}<time>{{ p.date }}</time>{% endif %}
  </li>
{% endfor %}
</ul>
```

---

## Page

An individual content file (`.md`).

### Core Properties

| Property | Type | Description |
|----------|------|-------------|
| page.title | String | Page title |
| page.description | String? | Page description |
| page.url | String | Relative URL path |
| page.permalink | String? | Absolute URL with base_url |
| page.section | String | Parent section name |
| page.date | String? | Publication date (YYYY-MM-DD) |
| page.updated | String? | Last updated date |
| page.language | String | Effective language code |
| page.translations | Array<TranslationLink> | Language variants |
| page.version | Object? | Documentation version (`nil` when unversioned) — see [page.version](#pageversion) |
| page.version_links | Array<VersionLink> | Version switcher rows (empty when unversioned) |

Rendered HTML content is available as the top-level `content` variable.

### Metadata Properties

| Property | Type | Description |
|----------|------|-------------|
| page.draft | Bool | Is draft |
| page.weight | Int | Sort weight |
| page.image | String? | Featured image path |
| page.authors | Array<String> | Author names |
| page.taxonomies | Object | This page's taxonomy terms (`page.taxonomies.tags`, `page.taxonomies.<name>`) |
| page.extra | Object | Custom front matter fields |

### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| page.word_count | Int | Word count |
| page.reading_time | Int | Reading time (minutes) |
| page.summary | String? | Summary HTML: the chunk before `<!-- more -->`, else `page.description`, else an automatic excerpt of the rendered body (`[content] summary_length`, one escaped `<p>`). Use with `\| safe` to embed (e.g. `{{ page.summary \| safe }}`); for `<meta name="description">` use `page.description` directly. |
| page.summary_truncated | Bool | `true` only when `page.summary` is an automatic excerpt that was cut short (useful for a "Read more" link). |
| page.assets | Array<String> | Static files in page bundle |
| page.series | String | Series name from front matter (empty if none) |
| page.series_index | Int | 1-based position within the series (requires `[series]` enabled) |
| page.series_pages | Array<Page> | All pages in the same series, sorted by `series_weight` |
| page.related_posts | Array<Page> | Pages sharing taxonomy terms (requires `[related]` enabled) |
| page.git | Object? | Commit metadata for the source file (requires `[git]` enabled; `nil` for uncommitted or generated pages). Fields: `hash`, `short_hash`, `lastmod` (Time), `first_commit` (Time), `author_name`, `author_email` — see [Git Metadata](/features/git-info/) |

### Boolean Flags

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| page.toc | Bool | false | Show table of contents |
| page.render | Bool | true | Should render |
| page.is_index | Bool | — | Is index file |
| page.generated | Bool | false | Auto-generated page |
| page.in_sitemap | Bool | true | Include in sitemap |
| page.in_search_index | Bool | true | Include in search |

### Navigation Properties

| Property | Type | Description |
|----------|------|-------------|
| page.lower | Page? | Previous page in reading order |
| page.higher | Page? | Next page in reading order |
| page.ancestors | Array<Page> | Parent section chain |
| page.translations | Array<TranslationLink> | Language variants |

### Custom Metadata

| Property | Type | Description |
|----------|------|-------------|
| page.extra | Object | Custom front matter fields |

### Flat Aliases

| Variable | Equivalent |
|----------|------------|
| page_title | page.title |
| page_description | page.description |
| page_url | page.url |
| page_section | page.section |
| page_date | page.date |
| page_image | page.image |
| page_summary | page.summary |
| page_word_count | page.word_count |
| page_reading_time | page.reading_time |
| page_permalink | page.permalink |
| page_authors | page.authors |
| page_weight | page.weight |
| page_language | page.language |
| page_translations | page.translations |
| taxonomy_name | Current taxonomy name (taxonomy pages) |
| taxonomy_term | Current taxonomy term (taxonomy term pages) |
| content | Rendered HTML content |

---

## Navigation Objects

### page.lower / page.higher

Navigation follows the flat reading order across the entire site, similar to mdBook or Docusaurus. Pages are ordered depth-first through the section tree: **section index → section pages → subsections (recursive)**. Within each section, pages are sorted by the section's `sort_by` setting (weight, date, or title).

| Property | Type | Description |
|----------|------|-------------|
| .title | String | Page title |
| .url | String | Page URL |
| .description | String? | Page description |
| .date | String? | Page date |

```jinja
<nav class="post-nav">
  {% if page.lower %}
  <a href="{{ page.lower.url }}">← {{ page.lower.title }}</a>
  {% endif %}
  
  {% if page.higher %}
  <a href="{{ page.higher.url }}">{{ page.higher.title }} →</a>
  {% endif %}
</nav>
```

### page.ancestors

Parent sections for breadcrumbs:

```jinja
<nav class="breadcrumbs">
  <a href="/">Home</a>
  {% for ancestor in page.ancestors %}
  / <a href="{{ ancestor.url }}">{{ ancestor.title }}</a>
  {% endfor %}
  / <span>{{ page.title }}</span>
</nav>
```

### page.version

Only on sites with `[[versions.list]]` (see [Versioned Docs](/features/versioned-docs/)). `nil` for pages outside every version directory.

| Property | Type | Description |
|----------|------|-------------|
| .name | String | Version name (URL segment, e.g. "v2") |
| .label | String | Display label |
| .latest | Bool | Is the latest version |
| .url | String | Root URL of the version in the page's language |

### page.version_links

One row per configured version, in config order.

| Property | Type | Description |
|----------|------|-------------|
| .name | String | Version name |
| .label | String | Display label |
| .latest | Bool | Is the latest version |
| .url | String | Same page in that version if it exists, else that version's root |
| .exists | Bool | Counterpart page exists |
| .current | Bool | Row is the page's own version |

```jinja
{% for v in page.version_links %}
<a href="{{ base_url }}{{ v.url }}"{% if v.current %} aria-current="page"{% endif %}>{{ v.label }}</a>
{% endfor %}
```

The global `versions` list (`{% for v in versions %}`, `versions.latest`, `versions.all`) exposes every version's root URL in the current page's language.

### page.translations

| Property | Type | Description |
|----------|------|-------------|
| .code | String | Language code (e.g., "en") |
| .url | String | Translated page URL |
| .title | String | Title in that language |
| .is_current | Bool | Current page's language |
| .is_default | Bool | Default language |

```jinja
{% if page.translations %}
<nav class="lang-switcher">
{% for t in page.translations %}
  {% if t.is_current %}
  <span>{{ t.code | upper }}</span>
  {% else %}
  <a href="{{ t.url }}">{{ t.code | upper }}</a>
  {% endif %}
{% endfor %}
</nav>
{% endif %}
```

---

## Accessing page.extra

Custom metadata from front matter:

```markdown
+++
title = "Review"

[extra]
rating = 4.5
featured = true
pros = ["Fast", "Reliable"]
+++
```

```jinja
{% if page.extra.featured %}
<span class="badge">Featured</span>
{% endif %}

<div class="rating">{{ page.extra.rating }} / 5</div>

<ul>
{% for pro in page.extra.pros %}
  <li>{{ pro }}</li>
{% endfor %}
</ul>
```

A top-level `outputs = ["json"]` in front matter is likewise an ordinary
unknown key that lands in `page.extra.outputs` — it overrides the
`[outputs]` config default for that one page/section. See
[Output Formats](/features/output-formats/).

---

### Time Variables

| Variable | Type | Description |
|----------|------|-------------|
| current_year | Int | Current year (e.g., 2025) |
| current_date | String | Current date (YYYY-MM-DD) |
| current_datetime | String | Current datetime |

```jinja
<footer>&copy; {{ current_year }} {{ site.title }}</footer>
```

---

### SEO Variables

**Pre-rendered HTML** (backward compatible):

| Variable | Description |
|----------|-------------|
| og_tags | OpenGraph meta tags |
| twitter_tags | Twitter Card meta tags |
| og_all_tags | Both OG and Twitter tags |
| canonical_tag | Canonical link tag |
| hreflang_tags | Hreflang alternate link tags (multilingual) |
| pagination_seo_links | `<link rel="prev/next">` tags |

```jinja
<head>
  {{ og_all_tags | safe }}
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
  {{ pagination_seo_links | safe }}
</head>
```

**Structured data** for custom meta tag markup:

| Property | Type | Description |
|----------|------|-------------|
| seo.canonical_url | String | Full canonical URL (base_url + page URL) |
| seo.og_type | String | OpenGraph type (default: "article") |
| seo.og_image | String | Resolved absolute image URL |
| seo.twitter_card | String | Twitter card type (default: "summary_large_image") |
| seo.twitter_site | String | Twitter site handle |
| seo.twitter_creator | String | Twitter creator handle |
| seo.fb_app_id | String | Facebook App ID |
| seo.hreflang | Array | Same as `page.translations` |

Page title, description, URL, and image are available as `page.title`, `page.description`, `page.url`, `page.image`. The `seo` object provides computed values specific to SEO (resolved URLs, config values).

```jinja
<head>
  <link rel="canonical" href="{{ seo.canonical_url }}">
  <meta property="og:title" content="{{ page.title }}">
  <meta property="og:type" content="{{ seo.og_type }}">
  <meta property="og:url" content="{{ seo.canonical_url }}">
  {% if page.description %}
  <meta property="og:description" content="{{ page.description }}">
  {% endif %}
  {% if seo.og_image %}
  <meta property="og:image" content="{{ seo.og_image }}">
  {% endif %}
  <meta name="twitter:card" content="{{ seo.twitter_card }}">
  {% if seo.twitter_site %}
  <meta name="twitter:site" content="{{ seo.twitter_site }}">
  {% endif %}
</head>
```

---

### Asset Variables

Pre-rendered `<link>` and `<script>` tags for convenience. These are generated from your `config.toml` settings.

| Variable | Description |
|----------|-------------|
| highlight_css | Syntax highlighting CSS `<link>` tag |
| highlight_js | Syntax highlighting JS `<script>` tag |
| highlight_tags | Both CSS and JS tags |
| auto_includes_css | Auto-included CSS `<link>` tags |
| auto_includes_js | Auto-included JS `<script>` tags |
| auto_includes | All auto-include tags |
| pwa_tags | PWA manifest link, theme-color meta, and service-worker registration (empty unless `[pwa]` is enabled) |

```jinja
<head>
  {{ highlight_css | safe }}
  {{ auto_includes_css | safe }}
</head>
<body>
  ...
  {{ highlight_js | safe }}
  {{ auto_includes_js | safe }}
</body>
```

---

### Table of Contents

Only available when `toc = true` in front matter.

**Pre-rendered HTML** (backward compatible):

| Variable | Type | Description |
|----------|------|-------------|
| toc | String | Generated TOC HTML |
| toc_obj.html | String | Same TOC HTML in object form |

```jinja
{% if page.toc %}
<aside class="toc">
  {{ toc | safe }}
</aside>
{% endif %}
```

**Structured data** for custom TOC markup:

| Property | Type | Description |
|----------|------|-------------|
| toc_obj.headers | Array | Structured TOC header objects |
| toc_obj.headers[].level | Int | Heading level (2-6) |
| toc_obj.headers[].id | String | Anchor ID |
| toc_obj.headers[].title | String | Heading text |
| toc_obj.headers[].permalink | String | Full anchor permalink |
| toc_obj.headers[].children | Array | Nested child headers (same structure) |

```jinja
{% if page.toc %}
<nav class="toc">
  <ul>
  {% for h in toc_obj.headers %}
    <li>
      <a href="{{ h.permalink }}">{{ h.title }}</a>
      {% if h.children %}
      <ul>
        {% for child in h.children %}
        <li><a href="{{ child.permalink }}">{{ child.title }}</a></li>
        {% endfor %}
      </ul>
      {% endif %}
    </li>
  {% endfor %}
  </ul>
</nav>
{% endif %}
```

---

### Paginator

Available in section and taxonomy term templates when pagination is enabled (`paginate` in [section front matter](/writing/sections/#front-matter), `paginate_by` for taxonomies). Page 1 lives at the section URL; later pages at `{url}/{paginate_path}/{n}/`.

| Property | Type | Description |
|----------|------|-------------|
| paginator.paginate_by | Int | Items per page |
| paginator.base_url | String | Pager base URL (`{url}/{paginate_path}/`) |
| paginator.number_pagers | Int | Total number of pages |
| paginator.first | String | First page URL |
| paginator.last | String | Last page URL |
| paginator.previous | String? | Previous page URL (nil on first page) |
| paginator.next | String? | Next page URL (nil on last page) |
| paginator.pages | Array<Page> | Pages on the current pager |
| paginator.current_index | Int | Current page number (1-based) |
| paginator.total_pages | Int | Same as `number_pagers` |

A `pagination_obj` variant exposes the same data as `previous_url`, `next_url`, `first_url`, `last_url`, `current_page`, `total_pages`, `total_items`, `per_page`, `has_previous`, `has_next`, and `html` (the pre-rendered nav, also available as the flat `pagination` variable).

```jinja
{% if paginator is defined and paginator.number_pagers > 1 %}
<nav>
  {% if paginator.previous %}<a href="{{ paginator.previous }}">Prev</a>{% endif %}
  <span>{{ paginator.current_index }} / {{ paginator.number_pagers }}</span>
  {% if paginator.next %}<a href="{{ paginator.next }}">Next</a>{% endif %}
</nav>
{% endif %}
```

---

### Taxonomy Variables

Available in taxonomy templates:

| Variable | Type | Description |
|----------|------|-------------|
| taxonomy_name | String | Taxonomy name (e.g., "tags") |
| taxonomy_term | String | Current term name (empty on the index page) |
| content | String | Pre-rendered listing HTML (terms or pages) |

For custom listings, use `get_taxonomy()` — see [Taxonomies](/writing/taxonomies/).

---

## Menus

`site.menus` exposes the **default language's** named menus (config `[[menus.*]]` + front-matter `menus`/`menu` registrations). Inside a template, prefer `get_menu(name="...")` over `site.menus.<name>` — it resolves against the **current page's** language instead, falling back to the default language:

```jinja
{% for item in get_menu(name="main") %}
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
{% endfor %}
```

### Entry Properties

| Property | Type | Description |
|----------|------|--------------|
| name | String | Display label |
| url | String | Bare root-relative path, or untouched external URL — comparable to `page.url` |
| href | String | `url` with the site's `base_path` applied (internal) or unchanged (external) — use this in `<a href>` |
| identifier | String | Unique key within the menu |
| weight | Int | Sort order |
| external | Bool | `true` for `http://`, `https://`, or `//` URLs |
| children | Array\<Entry\> | Nested entries whose `parent` matches this entry's `identifier` |
| page | Page? | The registering page's data (front-matter-registered entries only; nil for config-only entries and for entries registered on a section) |

See [Menus](/features/menus/) for the full config/front-matter reference, hierarchy, and per-language behavior.

---

## Type Reference

### Quick Reference

| Type | Description |
|------|-------------|
| String | Text value |
| String? | Optional text (may be nil) |
| Int | Integer number |
| Bool | true/false |
| Array<T> | List of type T |
| Object | Key-value map |

### Template Checking

```jinja
{# Check for nil #}
{% if page.description %}...{% endif %}

{# Check for empty array #}
{% if page.authors %}...{% endif %}

{# Check for empty string #}
{% if page.description is present %}...{% endif %}

{# Default value #}
{{ page.description | default(value=site.description) }}
```

---

## See Also

- [Template Syntax](/templates/syntax/) — Jinja2 basics
- [Functions](/templates/functions/) — Data retrieval functions
- [Filters](/templates/filters/) — Value transformation
