+++
title = "Search"
description = "Generate a client-side search index with Fuse.js"
weight = 2
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
| fields | array | ["title", "content"] | Fields to include in index |
| filename | string | "search.json" | Output filename |
| exclude | array | [] | Paths (prefixes) to exclude from search index |
| tokenize_cjk | bool | false | Enable CJK bigram tokenization |

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
