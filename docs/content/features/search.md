+++
title = "Search"
weight = 2
+++

Hwaro generates a search index that works with Fuse.js for client-side search.

## Configuration

Enable in `config.toml`:

```toml
[search]
enabled = true
include_content = true
exclude = ["/private", "/drafts"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Generate search index |
| include_content | bool | true | Include page content in index |
| exclude | array | [] | Paths (prefixes) to exclude from search index |

## Generated Files

When enabled, Hwaro generates `/search_index.json`:

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
| content | Page content (if `include_content = true`) |
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
fetch('/search_index.json')
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

## Performance Tips

### Large Sites

For sites with many pages:

1. Set `include_content = false` to reduce index size
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
  const res = await fetch('/search_index.json');
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
