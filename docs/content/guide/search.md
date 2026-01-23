+++
title = "Search"
description = "Add client-side search functionality to your Hwaro site"
+++


Hwaro can generate a search index that enables fast, client-side search on your site. This guide covers how to configure search and integrate it with your templates.

## Overview

Hwaro generates a JSON search index compatible with [Fuse.js](https://fusejs.io/), a lightweight fuzzy-search library. This allows visitors to search your site instantly without server-side infrastructure.

## Configuration

Enable search in your `config.toml`:

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content", "tags", "description"]
filename = "search.json"
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable search index generation |
| `format` | string | `"fuse_json"` | Index format (currently only `fuse_json`) |
| `fields` | array | `["title"]` | Fields to include in the index |
| `filename` | string | `"search.json"` | Output filename |

### Available Fields

| Field | Description |
|-------|-------------|
| `title` | Page title |
| `content` | Full page content (stripped of HTML) |
| `description` | Page description from front matter |
| `tags` | Page tags |
| `url` | Page URL |
| `section` | Section the page belongs to |

## Search Index Format

The generated `search.json` contains an array of page objects:

```json
[
  {
    "title": "Installation Guide",
    "content": "Learn how to install Hwaro on your system...",
    "description": "Step-by-step installation instructions",
    "tags": ["getting-started", "installation"],
    "url": "/getting-started/installation/",
    "section": "getting-started"
  },
  {
    "title": "Configuration",
    "content": "Hwaro uses a TOML configuration file...",
    "description": "Configure your Hwaro site",
    "tags": ["configuration", "setup"],
    "url": "/getting-started/configuration/",
    "section": "getting-started"
  }
]
```

## Implementing Search with Fuse.js

### 1. Include Fuse.js

Add Fuse.js to your site via CDN or npm:

```html
<!-- Via CDN in your template -->
<script src="https://cdn.jsdelivr.net/npm/fuse.js@7.0.0"></script>
```

Or install via npm:

```bash
npm install fuse.js
```

### 2. Create Search UI

Add a search interface to your template:

```html
<div class="search-container">
  <input 
    type="search" 
    id="search-input" 
    placeholder="Search documentation..."
    autocomplete="off"
  >
  <div id="search-results" class="search-results"></div>
</div>
```

### 3. Initialize Search

Create a search script:

```javascript
// Load search index and initialize Fuse.js
let fuse;

async function initSearch() {
  const response = await fetch('/search.json');
  const searchIndex = await response.json();
  
  fuse = new Fuse(searchIndex, {
    keys: [
      { name: 'title', weight: 2 },
      { name: 'description', weight: 1.5 },
      { name: 'content', weight: 1 },
      { name: 'tags', weight: 1.5 }
    ],
    threshold: 0.3,
    includeMatches: true,
    minMatchCharLength: 2
  });
}

// Perform search
function search(query) {
  if (!fuse || !query) {
    return [];
  }
  return fuse.search(query, { limit: 10 });
}

// Render results
function renderResults(results) {
  const container = document.getElementById('search-results');
  
  if (results.length === 0) {
    container.innerHTML = '<p class="no-results">No results found</p>';
    return;
  }
  
  const html = results.map(result => `
    <a href="${result.item.url}" class="search-result">
      <h3>${result.item.title}</h3>
      <p>${result.item.description || ''}</p>
    </a>
  `).join('');
  
  container.innerHTML = html;
}

// Event listener
document.getElementById('search-input').addEventListener('input', (e) => {
  const query = e.target.value;
  if (query.length >= 2) {
    const results = search(query);
    renderResults(results);
  } else {
    document.getElementById('search-results').innerHTML = '';
  }
});

// Initialize on page load
initSearch();
```

### 4. Style the Search

Add CSS for your search interface:

```css
.search-container {
  position: relative;
  max-width: 400px;
}

#search-input {
  width: 100%;
  padding: 0.75rem 1rem;
  background: var(--bg-subtle);
  border: 1px solid var(--border);
  border-radius: 8px;
  color: var(--text);
  font-size: 0.9rem;
}

#search-input:focus {
  outline: none;
  border-color: var(--primary);
}

#search-input::placeholder {
  color: var(--text-muted);
}

.search-results {
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  background: var(--bg-subtle);
  border: 1px solid var(--border);
  border-radius: 8px;
  margin-top: 0.5rem;
  max-height: 400px;
  overflow-y: auto;
  z-index: 100;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
}

.search-result {
  display: block;
  padding: 0.75rem 1rem;
  text-decoration: none;
  border-bottom: 1px solid var(--border);
  transition: background 0.15s;
}

.search-result:last-child {
  border-bottom: none;
}

.search-result:hover {
  background: var(--bg-hover);
}

.search-result h3 {
  margin: 0 0 0.25rem 0;
  font-size: 0.95rem;
  color: var(--text);
}

.search-result p {
  margin: 0;
  font-size: 0.85rem;
  color: var(--text-muted);
}

.no-results {
  padding: 1rem;
  text-align: center;
  color: var(--text-muted);
}
```

## Fuse.js Configuration

Customize Fuse.js for your needs:

### Key Weights

Prioritize certain fields:

```javascript
keys: [
  { name: 'title', weight: 2 },      // Title matches are most important
  { name: 'description', weight: 1.5 },
  { name: 'tags', weight: 1.5 },
  { name: 'content', weight: 1 }     // Content has lower priority
]
```

### Threshold

Control fuzzy matching sensitivity (0 = exact, 1 = match anything):

```javascript
threshold: 0.3  // Recommended for documentation
```

### Other Options

```javascript
{
  includeMatches: true,     // Include match positions
  minMatchCharLength: 2,    // Minimum characters to match
  ignoreLocation: true,     // Match anywhere in string
  findAllMatches: true      // Find all matches, not just first
}
```

## Advanced Search Features

### Keyboard Navigation

Add keyboard support:

```javascript
const input = document.getElementById('search-input');
const resultsContainer = document.getElementById('search-results');
let selectedIndex = -1;

input.addEventListener('keydown', (e) => {
  const results = resultsContainer.querySelectorAll('.search-result');
  
  if (e.key === 'ArrowDown') {
    e.preventDefault();
    selectedIndex = Math.min(selectedIndex + 1, results.length - 1);
    updateSelection(results);
  } else if (e.key === 'ArrowUp') {
    e.preventDefault();
    selectedIndex = Math.max(selectedIndex - 1, -1);
    updateSelection(results);
  } else if (e.key === 'Enter' && selectedIndex >= 0) {
    e.preventDefault();
    results[selectedIndex].click();
  } else if (e.key === 'Escape') {
    input.blur();
    resultsContainer.innerHTML = '';
  }
});

function updateSelection(results) {
  results.forEach((r, i) => {
    r.classList.toggle('selected', i === selectedIndex);
  });
}
```

### Search Highlighting

Highlight matches in results:

```javascript
function highlightMatches(text, matches) {
  if (!matches || matches.length === 0) return text;
  
  let result = '';
  let lastIndex = 0;
  
  matches.forEach(match => {
    match.indices.forEach(([start, end]) => {
      result += text.slice(lastIndex, start);
      result += `<mark>${text.slice(start, end + 1)}</mark>`;
      lastIndex = end + 1;
    });
  });
  
  result += text.slice(lastIndex);
  return result;
}
```

### Debounced Search

Improve performance with debouncing:

```javascript
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    clearTimeout(timeout);
    timeout = setTimeout(() => func.apply(this, args), wait);
  };
}

const debouncedSearch = debounce((query) => {
  const results = search(query);
  renderResults(results);
}, 200);

input.addEventListener('input', (e) => {
  const query = e.target.value;
  if (query.length >= 2) {
    debouncedSearch(query);
  } else {
    resultsContainer.innerHTML = '';
  }
});
```

## Search Modal

Create a full-screen search modal:

```html
<div id="search-modal" class="search-modal" hidden>
  <div class="search-modal-content">
    <input type="search" id="modal-search-input" placeholder="Search...">
    <div id="modal-search-results"></div>
    <div class="search-hint">
      <kbd>↑↓</kbd> to navigate
      <kbd>Enter</kbd> to select
      <kbd>Esc</kbd> to close
    </div>
  </div>
</div>
```

```css
.search-modal {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.8);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding-top: 20vh;
  z-index: 1000;
}

.search-modal-content {
  background: var(--bg-subtle);
  border: 1px solid var(--border);
  border-radius: 12px;
  width: 100%;
  max-width: 600px;
  padding: 1rem;
}

.search-hint {
  display: flex;
  gap: 1rem;
  justify-content: center;
  padding-top: 1rem;
  color: var(--text-muted);
  font-size: 0.8rem;
}

.search-hint kbd {
  background: var(--bg);
  padding: 0.2rem 0.5rem;
  border-radius: 4px;
  font-family: inherit;
}
```

Open with keyboard shortcut:

```javascript
document.addEventListener('keydown', (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
    e.preventDefault();
    document.getElementById('search-modal').hidden = false;
    document.getElementById('modal-search-input').focus();
  }
});
```

## Performance Tips

### 1. Limit Content Length

For large sites, truncate content in the index:

```toml
[search]
fields = ["title", "description", "tags"]  # Exclude full content
```

### 2. Lazy Load Search

Only load search functionality when needed:

```javascript
let searchLoaded = false;

async function loadSearch() {
  if (searchLoaded) return;
  
  // Load Fuse.js dynamically
  await import('https://cdn.jsdelivr.net/npm/fuse.js@7.0.0/dist/fuse.mjs');
  await initSearch();
  searchLoaded = true;
}

document.getElementById('search-input').addEventListener('focus', loadSearch);
```

### 3. Cache Search Index

The search index is static, so browsers cache it automatically. Ensure your server sends appropriate cache headers.

## Best Practices

1. **Include descriptions** — Add descriptions to all pages for better search results
2. **Use meaningful titles** — Clear titles improve search accuracy
3. **Tag content appropriately** — Tags help narrow search results
4. **Provide visual feedback** — Show loading states and "no results" messages
5. **Support keyboard navigation** — Many users prefer keyboard shortcuts
6. **Test on mobile** — Ensure search works well on touch devices

## Next Steps

- Configure [SEO Features](/guide/seo/) for better discoverability
- Learn about [Taxonomies](/guide/taxonomies/) for content organization
- See [Configuration Reference](/reference/config/) for all search options