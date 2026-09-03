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

A single `search.json` grows with the site, and every visitor pays for the whole file before the first search. Sharding splits the index into several JSON files plus a manifest so a client can load only what it needs — the current section first, or one language at a time.

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

Each shard is a plain JSON array with exactly the same entry schema as `search.json` (shards are always JSON, whatever `format` says — the `*_javascript` wrapper only serves `<script src>` loading). `search/index.json` describes the layout:

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

- `url` honors `base_url`'s subpath (`/docs/search/blog.json` on a `https://example.com/docs` deploy) and percent-encodes section names.
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
