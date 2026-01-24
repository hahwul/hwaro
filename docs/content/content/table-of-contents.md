+++
title = "Table of Contents"
+++

Hwaro can automatically generate a table of contents from your page headings.

## Enable TOC

Add `toc = true` to front matter:

```markdown
+++
title = "My Page"
toc = true
+++

## First Section
Content here.

## Second Section
More content.

### Subsection
Details here.
```

## Template Variable

Use `{{ toc }}` in your template:

```jinja
{% extends "base.html" %}

{% block content %}
<div class="page-layout">
  <aside class="toc">
    <h2>On this page</h2>
    {{ toc }}
  </aside>
  
  <article>
    {{ content }}
  </article>
</div>
{% endblock %}
```

## Generated HTML

The `{{ toc }}` variable outputs a nested list:

```html
<ul>
  <li><a href="#first-section">First Section</a></li>
  <li>
    <a href="#second-section">Second Section</a>
    <ul>
      <li><a href="#subsection">Subsection</a></li>
    </ul>
  </li>
</ul>
```

## Heading Levels

TOC is generated from `h2`-`h6` headings. The `h1` (page title) is excluded.

| Markdown | Heading | In TOC |
|----------|---------|--------|
| `# Title` | h1 | No |
| `## Section` | h2 | Yes |
| `### Subsection` | h3 | Yes |
| `#### Details` | h4 | Yes |

## Styling

Example CSS for TOC sidebar:

```css
.toc {
  position: sticky;
  top: 80px;
  padding: 1rem;
  border-left: 1px solid var(--border);
}

.toc ul {
  list-style: none;
  padding: 0;
  margin: 0;
}

.toc li {
  margin-bottom: 0.5rem;
}

.toc a {
  color: var(--text-muted);
  text-decoration: none;
  font-size: 0.875rem;
}

.toc a:hover {
  color: var(--primary);
}

/* Nested levels */
.toc ul ul {
  padding-left: 1rem;
  margin-top: 0.5rem;
}

.toc ul ul a {
  font-size: 0.8rem;
}
```

## Conditional Display

Only show TOC when enabled:

```jinja
{% if page.toc %}
<aside class="toc">
  {{ toc }}
</aside>
{% endif %}
```
