+++
title = "Search"
+++

Hwaro generates a JSON search index compatible with [Fuse.js](https://fusejs.io/) or [Elasticlunr.js](http://elasticlunr.com/) for client-side search.

## Configuration

```toml
[search]
enabled = true
format = "fuse_json" # or elasticlunr_json
fields = ["title", "content", "tags", "description"]
filename = "search.json"
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `false` | Enable search index |
| `format` | `"fuse_json"` | Index format (`fuse_json`, `fuse_javascript`, `elasticlunr_json`, `elasticlunr_javascript`) |
| `fields` | `["title"]` | Fields to index |
| `filename` | `"search.json"` | Output filename |

## Available Fields

| Field | Description |
|-------|-------------|
| `title` | Page title |
| `content` | Page content (HTML stripped) |
| `description` | Page description |
| `tags` | Page tags |
| `url` | Page URL |
| `section` | Section name |

## Index Format

The generated `search.json` is an array of documents:

```json
[
  {
    "title": "Installation",
    "content": "How to install Hwaro...",
    "url": "/getting-started/installation/",
    "section": "getting-started"
  }
]
```

This format is compatible with both Fuse.js and Elasticlunr.js.

---

## Fuse.js Implementation

### 1. Include Fuse.js

```html
<script src="https://cdn.jsdelivr.net/npm/fuse.js@7.0.0"></script>
```

### 2. Create Search UI

```html
<input type="search" id="search-input" placeholder="Search...">
<div id="search-results"></div>
```

### 3. Initialize Search

```javascript
let fuse;

async function initSearch() {
  const response = await fetch('/search.json');
  const data = await response.json();
  
  fuse = new Fuse(data, {
    keys: [
      { name: 'title', weight: 2 },
      { name: 'description', weight: 1.5 },
      { name: 'content', weight: 1 }
    ],
    threshold: 0.3
  });
}

document.getElementById('search-input').addEventListener('input', (e) => {
  const query = e.target.value;
  if (query.length < 2) return;
  
  const results = fuse.search(query, { limit: 10 });
  renderResults(results.map(r => r.item));
});

function renderResults(results) {
  const container = document.getElementById('search-results');
  
  if (!results.length) {
    container.innerHTML = '<p>No results found</p>';
    return;
  }
  
  container.innerHTML = results.map(item => `
    <a href="${item.url}">
      <strong>${item.title}</strong>
      <span>${item.description || ''}</span>
    </a>
  `).join('');
}

initSearch();
```

---

## Elasticlunr.js Implementation

### 1. Include Elasticlunr.js

```html
<script src="https://cdn.jsdelivr.net/npm/elasticlunr@0.9.5/dist/elasticlunr.min.js"></script>
```

### 2. Create Search UI

```html
<input type="search" id="search-input" placeholder="Search...">
<div id="search-results"></div>
```

### 3. Initialize Search

```javascript
let index;

async function initSearch() {
  const response = await fetch('/search.json');
  const data = await response.json();
  
  index = elasticlunr(function () {
    this.setRef('url');
    this.addField('title');
    this.addField('description');
    this.addField('content');
    
    data.forEach(doc => this.addDoc(doc));
  });
}

document.getElementById('search-input').addEventListener('input', (e) => {
  const query = e.target.value;
  if (query.length < 2) return;
  
  const results = index.search(query, {
    fields: {
      title: { bool: "AND", expand: true },
      description: { bool: "AND", expand: true },
      content: { bool: "AND", expand: true }
    },
    expand: true
  });
  
  const documents = results.map(r => index.documentStore.getDoc(r.ref));
  renderResults(documents);
});

function renderResults(results) {
  const container = document.getElementById('search-results');
  
  if (!results.length) {
    container.innerHTML = '<p>No results found</p>';
    return;
  }
  
  container.innerHTML = results.map(item => `
    <a href="${item.url}">
      <strong>${item.title}</strong>
      <span>${item.description || ''}</span>
    </a>
  `).join('');
}

initSearch();
```

## Keyboard Shortcut

Open search with `Cmd/Ctrl + K`:

```javascript
document.addEventListener('keydown', (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
    e.preventDefault();
    document.getElementById('search-input').focus();
  }
});
```

## Styling

```css
#search-results {
  position: absolute;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  max-height: 400px;
  overflow-y: auto;
}

#search-results a {
  display: block;
  padding: 0.75rem 1rem;
  text-decoration: none;
  border-bottom: 1px solid var(--border);
}

#search-results a:hover {
  background: var(--bg-subtle);
}
```

## Performance Tips

- Limit fields indexed for large sites
- Lazy-load the search library on first search focus
- Use debouncing for search input
