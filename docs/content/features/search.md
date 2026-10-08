+++
title = "Search"
description = "Generate a client-side search index with Fuse.js"
weight = 5
+++

Hwaro generates a search index that works with Fuse.js for client-side search.

## Configuration

Enable in `config.toml`:

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content", "description", "tags", "url", "section"]
filename = "search.json"
exclude = ["/private", "/drafts"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Generate search index |
| format | string | "fuse_json" | Search index format |
| fields | array | ["title", "content"] | Fields to include in index — by default only `title` and `content` (`url` is always added) |
| filename | string | "search.json" | Output filename |
| exclude | array | [] | Paths (prefixes) to exclude from search index |
| tokenize_cjk | bool | false | Enable CJK bigram tokenization |
| shards | string | "none" | Split the index into lazy-loadable shards: `"section"`, `"language"`, or `"section-language"` — see [Sharded index](#sharded-index) |
| single_file | bool | true | With `shards` on, keep emitting the classic `search.json` alongside the shards; `false` emits shards only |
| content_max_length | int | 0 | When > 0, truncate each entry's `content` to that many characters at a word boundary; `0` keeps the full text |
| split_by_heading | bool | false | Also emit one record per h2/h3 section that deep-links to `#heading` — see [Heading-level records](#heading-level-records) |
| facets | array | [] | Filterable fields added to every record: `"section"`, `"lang"`, `"tags"` or any taxonomy name — see [Facets](#facets) |
| ui | bool | false | Publish the built-in search UI and fill `{{ search_tags }}` — see [Built-in UI](#built-in-ui). Needs a JSON `format` |

## Generated Files

When enabled, Hwaro generates `/search.json` (configurable via `filename`):

```json
[
  {
    "title": "My Post",
    "url": "/blog/my-post/",
    "content": "Page content...",
    "description": "Post description",
    "section": "blog",
    "tags": ["tutorial"]
  }
]
```

## Fields Indexed

Only fields listed in `fields` are emitted (`url` is always included):

| Field | Description |
|-------|-------------|
| title | Page title |
| url | Page URL |
| content | Page content (if `"content"` is in `fields`) |
| description | Page description |
| section | Section name |
| tags | Page tags |

## Built-in UI

Hwaro ships a small search UI, so a site does not have to write its own client. It has no dependencies and makes no requests to other hosts.

```toml
[search]
enabled = true
format = "fuse_json"        # or "elasticlunr_json"; a *_javascript format is a config error
ui = true
split_by_heading = true     # optional: results deep-link to sections
facets = ["section", "tags"] # optional: filter chips
```

Put `{{ search_tags }}` in your `<head>`, and add a button that opens the search:

```jinja
<head>
  {{ search_tags }}
</head>
<body>
  <button type="button" data-hwaro-search>Search</button>
  ...
</body>
```

With `ui = true`, the build writes `assets/hwaro-search/search.js` and `assets/hwaro-search/search.css`. `search_tags` holds a `<link>` and a `<script defer>` tag for them:

- Both URLs carry the `base_url` subpath and a `?v=` cache-busting hash.
- With `[assets] sri = true` they also get `integrity` and `crossorigin` (not under `hwaro serve`).
- The script reads its settings from a `data-hwaro-search-config` attribute, so the page needs no inline script. This keeps it working under a strict Content-Security-Policy.

`search_tags` is an empty string while `ui` is off, so a template can include it unconditionally.

### Behaviour

- **Opening:** press `/` or `Cmd/Ctrl+K`, or click any element with `data-hwaro-search`. The search opens in a modal dialog. If the page has an element with `data-hwaro-search-input`, the UI mounts inside that element instead (inline search box), and the shortcuts focus it.
- **Loading:** the index is fetched on first open, never on page load. With `shards`, the UI reads `search/index.json` and loads only the current language's shards.
- **Matching:** case-insensitive prefix and substring matching on every word of the query, all words required. Title matches rank above heading matches, and heading matches above content matches. With `tokenize_cjk = true`, the query is split into the same CJK bigrams as the index. At most 20 results are shown.
- **Results:** each result shows the title (› heading), plus an excerpt with the matched words highlighted, and links to the page or to `#heading`.
- **Facets:** with `facets` set, chips for the values found in the results filter the list.
- **Language:** on a multilingual site, results are limited to the page's language.
- **Keyboard and accessibility:** ↑/↓ move through results, Enter opens one, Esc closes. The input is an ARIA combobox over a listbox, the dialog traps focus, and the result count is announced through an `aria-live` region.
- **Security:** index text reaches the page only as text nodes, never as HTML, and only same-origin `http(s)` URLs from the index are linked.

### Styling

The stylesheet uses CSS custom properties and follows `prefers-color-scheme` (and `data-theme="dark"`/`"light"` on `<html>`). Override them in your own CSS:

```css
.hwaro-search-overlay, .hwaro-search-inline {
  --hwaro-search-accent: #c2410c;
  --hwaro-search-radius: 4px;
  --hwaro-search-font: "Inter", sans-serif;
}
```

The other properties are `--hwaro-search-bg`, `-fg`, `-muted`, `-border`, `-active`, `-mark` and `-backdrop`.

The build always writes its own `assets/hwaro-search/` files. A file at the same path under `static/` is replaced, and the build warns about it.

### Translations

The UI text comes from `i18n/<lang>.toml`. English is the built-in default for every key:

```toml
# i18n/ko.toml
[search]
placeholder = "검색"
no_results = "결과 없음"
results_count = "{count}개 결과"   # {count} is replaced by the number
close = "닫기"
```

For different singular and plural forms, use a table instead (the same one/other rule as the `pluralize` filter):

```toml
[search.results_count]
one = "{count} result"
other = "{count} results"
```

A missing key falls back to the default language, then to English.

## Heading-Level Records

With `split_by_heading = true`, every page also gets one record per `h2`/`h3` section, so a result can land on the right part of a long page:

```json
{"title": "Install", "content": "Run the installer...", "url": "/docs/install/", "lang": "en"},
{"title": "Install", "content": "Download the binary...", "url": "/docs/install/#macos", "lang": "en", "heading": "macOS"}
```

- The page record is unchanged (byte-identical to a build without the option).
- `url` uses the heading's real `id` from the rendered page, including custom ids (`## macOS {#mac}`).
- `content` is the section's text up to the next `h2`/`h3`, with the same HTML stripping, `tokenize_cjk` and `content_max_length` as page content. `h4`–`h6` stay inside their section.
- The record also carries the page's other configured `fields`, `lang`, `version` and facets.
- A heading without an id ends the previous section but gets no record of its own.
- Section records follow the same eligibility as their page (`exclude`, `in_search_index = false`, drafts, `[versions] search`, per-language `build_search_index`). With `shards`, they go to their page's shard. The manifest's `fields` list gains `heading`.

## Facets

`facets` adds filterable fields to every record (page and section records):

```toml
[search]
facets = ["section", "lang", "tags", "category"]
```

| Facet | Value |
|-------|-------|
| `section` | The page's section path (`blog/news`) |
| `lang` | The page language (already on every record) |
| `tags` | The page's tags |
| any taxonomy name | That taxonomy's terms for the page (an empty list when it has none) |

An unknown name is ignored with a warning that lists the valid names. The built-in UI turns the facets into filter chips; a custom client can filter on the fields directly.

## Client-Side Implementation

### Using Fuse.js

Add to your template:

```html
<script src="https://cdn.jsdelivr.net/npm/fuse.js@7.0.0"></script>
<script>
let searchIndex = [];

// Load index
fetch('/search.json')
  .then(res => res.json())
  .then(data => {
    searchIndex = data;
  });

// Initialize Fuse.js
function search(query) {
  const fuse = new Fuse(searchIndex, {
    keys: ['title', 'content', 'description', 'tags'],
    threshold: 0.3
  });
  return fuse.search(query);
}
</script>
```

### Search Form

```html
<form id="search-form">
  <input type="search" id="search-input" placeholder="Search...">
</form>

<div id="search-results"></div>

<script>
const input = document.getElementById('search-input');
const results = document.getElementById('search-results');

input.addEventListener('input', (e) => {
  const query = e.target.value;
  if (query.length < 2) {
    results.innerHTML = '';
    return;
  }
  
  const matches = search(query);
  results.innerHTML = matches
    .slice(0, 10)
    .map(m => `
      <a href="${m.item.url}">
        <h3>${m.item.title}</h3>
        <p>${m.item.description || ''}</p>
      </a>
    `)
    .join('');
});
</script>
```

## CJK Search Support

For sites with Chinese, Japanese, or Korean content, enable CJK tokenization to improve search accuracy. CJK languages often lack spaces between words, making it difficult for search libraries to tokenize text properly.

When enabled, CJK character runs are split into overlapping bigrams (2-character pairs), allowing search terms to match within longer text.

**Example:** `"검색엔진"` → `"검색 색엔 엔진"` (search query `"검색"` now matches)

### Configuration

```toml
[search]
enabled = true
tokenize_cjk = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| tokenize_cjk | bool | false | Enable CJK bigram tokenization for search index |

### How It Works

- Only `title`, `content`, and `description` fields are tokenized
- `url`, `tags`, and `section` fields are left unchanged (structural fields)
- Non-CJK text passes through unmodified
- Works with both Fuse.js and ElasticLunr formats

### Notes

- Enabling this option slightly increases the search index size
- The bigram approach works well for most CJK search scenarios
- Korean text with natural spaces (e.g., `"검색 엔진"`) is handled correctly

## Excluding Pages

### Front Matter

Exclude individual pages from search with front matter:

```markdown
+++
title = "Terms of Service"
in_search_index = false
+++
```

### Configuration

Exclude entire sections or paths using `config.toml`:

```toml
[search]
exclude = ["/private", "/drafts"]
```

### Field Selection

Control which fields appear in the search index by specifying `fields`:

```toml
[search]
enabled = true
fields = ["title", "description", "tags", "url"]
```

Available fields: `title`, `content`, `description`, `tags`, `url`, `section`.

Omitting `content` from `fields` significantly reduces the index file size for large sites.

## Performance Tips

### Large Sites

For sites with many pages:

1. Remove `"content"` from `fields` to reduce index size
2. Use Fuse.js `ignoreLocation` option
3. Implement debounced search

```javascript
function debounce(fn, delay) {
  let timeout;
  return (...args) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => fn(...args), delay);
  };
}

input.addEventListener('input', debounce((e) => {
  // search logic
}, 200));
```

### Lazy Loading

Load index only when search is focused:

```javascript
let indexLoaded = false;

input.addEventListener('focus', async () => {
  if (indexLoaded) return;
  const res = await fetch('/search.json');
  searchIndex = await res.json();
  indexLoaded = true;
});
```

## Sharded Index

A single `search.json` grows with the site, and every visitor pays for the whole file before the first search. Sharding splits the index into several JSON files plus a manifest so a client can load only what it needs: the current section first, or one language at a time.

```toml
[search]
enabled = true
shards = "section"          # "section" | "language" | "section-language"
single_file = false         # emit shards only (default true keeps search.json too)
content_max_length = 500    # optional: cap each entry's content
```

| Mode | Shards | Example ids |
|------|--------|-------------|
| `"section"` | One per top-level content section; pages outside any section go to `_root` | `blog`, `docs`, `_root` |
| `"language"` | One per language (multilingual sites); the default language uses its code | `en`, `ko` |
| `"section-language"` | Language, then section | `en/blog`, `ko/blog`, `ko/_root` |

Nested sections fold into their top-level section: `blog/news/post.md` lands in the `blog` shard. Every eligibility rule of the classic index applies unchanged (`fields`, `exclude`, `in_search_index = false`, drafts, `render = false`, per-language `build_search_index`, `tokenize_cjk`).

### Generated Files

```
public/
├── search.json          # unless single_file = false
└── search/
    ├── index.json       # manifest
    ├── _root.json
    ├── blog.json
    └── docs.json        # nested ids use directories: search/ko/blog.json
```

Each shard is a plain JSON array with exactly the same entry schema as `search.json` (shards are always JSON, whatever `format` says; the `*_javascript` wrapper only serves `<script src>` loading). `search/index.json` describes the layout:

```json
{
  "version": 1,
  "fields": ["title", "content", "url", "lang"],
  "shards": [
    {"id": "_root", "url": "/search/_root.json", "language": null, "section": "", "count": 2, "bytes": 200},
    {"id": "blog",  "url": "/search/blog.json",  "language": null, "section": "blog", "count": 42, "bytes": 12345}
  ]
}
```

- `url` honors `base_url`'s subpath (`/docs/search/blog.json` on a `https://example.com/docs` deploy) and percent-encodes section names. Always load a shard through its manifest `url`: a section (or language) named `index` is written to `search/_index.json` so it cannot collide with the manifest at `search/index.json`.
- `language` is set in the `language` and `section-language` modes, `section` in the `section` and `section-language` modes; the other is `null`.
- Shards are listed in id order and the file never carries a timestamp, so the output is deterministic and diff-friendly. A shard whose last page disappears is removed on the next build.
- `--cache` builds and `hwaro serve` regenerate the shards from the same page set as `search.json`.

### Lazy-Loading Shards with Fuse.js

Fetch the manifest once, then load shards on demand. A global search box loads all of them; a section-aware one loads the current section's shard first and the rest in the background:

```html
<script src="https://cdn.jsdelivr.net/npm/fuse.js@7.0.0"></script>
<script>
const loaded = new Map();       // shard id → entries
let manifest = null;
let fuse = null;

async function loadManifest() {
  if (manifest) return manifest;
  manifest = await (await fetch('/search/index.json')).json();
  return manifest;
}

async function loadShard(shard) {
  if (loaded.has(shard.id)) return;
  loaded.set(shard.id, await (await fetch(shard.url)).json());
  fuse = new Fuse([...loaded.values()].flat(), {
    keys: ['title', 'content', 'description', 'tags'],
    threshold: 0.3,
    ignoreLocation: true
  });
}

// Which shards matter for this page? Match the manifest against the
// document language and the first URL segment; fall back to everything.
async function loadRelevantShards() {
  const { shards } = await loadManifest();
  const lang = (document.documentElement.lang || '').split('-')[0];
  const section = location.pathname.split('/').filter(Boolean)[0] || '';
  const local = shards.filter(s =>
    (s.language === null || s.language === lang) &&
    (s.section === null || s.section === section));
  await Promise.all((local.length ? local : shards).map(loadShard));
  // Warm the remaining shards without blocking the first results.
  shards.filter(s => !loaded.has(s.id)).forEach(s => loadShard(s));
}

function search(query) {
  return fuse ? fuse.search(query) : [];
}

document.getElementById('search-input').addEventListener('focus', loadRelevantShards, { once: true });
</script>
```

For a purely global box replace `loadRelevantShards` with `shards.map(loadShard)`. Everything after loading is the same Fuse.js code as the single-file setup above.

## Alternative: Pagefind

For larger sites, consider [Pagefind](https://pagefind.app/):

```bash
# After build
npx pagefind --site public
```

Add to config as post-build hook:

```toml
[build]
hooks.post = ["npx pagefind --site public"]
```

## See Also

- [Configuration](/start/config/) — Search config reference
- [Multilingual](/features/multilingual/) — CJK tokenization and i18n search
