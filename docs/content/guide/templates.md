+++
title = "Templates"
description = "Learn how to customize your site's appearance with ECR templates"
+++


Hwaro uses ECR (Embedded Crystal) templates for rendering pages. Templates give you complete control over your site's HTML structure and design.

## Template Directory

All templates are stored in the `templates/` directory:

```
templates/
├── header.ecr          # Common header partial (HTML head, navigation)
├── footer.ecr          # Common footer partial
├── page.ecr            # Regular page template
├── section.ecr         # Section index template
├── index.ecr           # Homepage template (optional)
├── taxonomy.ecr        # Taxonomy listing template
├── taxonomy_term.ecr   # Individual taxonomy term template
├── 404.ecr             # 404 error page template
└── shortcodes/         # Shortcode templates
    └── alert.ecr
```

## Template Types

### Page Template (`page.ecr`)

Used for regular content pages:

```erb
<%= render "header" %>
<header class="site-header">
  <a href="<%= base_url %>/" class="logo"><%= site_title %></a>
</header>
<main>
  <article>
    <h1><%= page_title %></h1>
    <%= content %>
  </article>
</main>
<%= render "footer" %>
```

### Section Template (`section.ecr`)

Used for section index pages (content directories with `_index.md`):

```erb
<%= render "header" %>
<main>
  <h1><%= page_title %></h1>
  <%= content %>
  
  <h2>Pages in this Section</h2>
  <ul class="section-list">
    <%= section_list %>
  </ul>
</main>
<%= render "footer" %>
```

### Index Template (`index.ecr`)

Optional template for the homepage. If not present, `page.ecr` is used:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title><%= site_title %></title>
</head>
<body>
  <header>
    <h1>Welcome to <%= site_title %></h1>
  </header>
  <main>
    <%= content %>
  </main>
</body>
</html>
```

### Header Partial (`header.ecr`)

Contains the HTML document head and opening body tag:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="description" content="<%= page_description %>">
  <title><%= page_title %> - <%= site_title %></title>
  <%= og_all_tags %>
  <%= highlight_css %>
  <%= auto_includes_css %>
  <style>
    /* Your CSS here */
  </style>
</head>
<body>
```

### Footer Partial (`footer.ecr`)

Contains closing elements and scripts:

```erb
  <footer>
    <p>&copy; 2024 <%= site_title %></p>
  </footer>
  <%= highlight_js %>
  <%= auto_includes_js %>
</body>
</html>
```

## ECR Syntax

ECR (Embedded Crystal) uses Ruby-like syntax for embedding dynamic content:

### Output Expression

Output the result of an expression:

```erb
<%= page_title %>
<%= site_title %>
```

### Control Structures

Use Crystal control structures (note: usually not needed in simple templates):

```erb
<% if page_title != "" %>
  <h1><%= page_title %></h1>
<% end %>
```

### Including Partials

Include other template files:

```erb
<%= render "header" %>
<%= render "footer" %>
```

The partial name is relative to the `templates/` directory, without the `.ecr` extension.

## Available Variables

### Site Variables

| Variable | Type | Description |
|----------|------|-------------|
| `site_title` | String | Site title from config |
| `base_url` | String | Base URL from config |
| `site_description` | String | Site description from config |

### Page Variables

| Variable | Type | Description |
|----------|------|-------------|
| `page_title` | String | Current page title |
| `page_description` | String | Page description (falls back to site description) |
| `page_url` | String | Current page URL path |
| `page_section` | String | Section the page belongs to |
| `page_image` | String | Page image (for social sharing) |
| `content` | String | Rendered page content |

### Section Variables

| Variable | Type | Description |
|----------|------|-------------|
| `section_list` | String | HTML list of pages in the section |

### SEO Variables

| Variable | Type | Description |
|----------|------|-------------|
| `og_tags` | String | OpenGraph meta tags |
| `twitter_tags` | String | Twitter Card meta tags |
| `og_all_tags` | String | Both OG and Twitter tags combined |

### Asset Variables

| Variable | Type | Description |
|----------|------|-------------|
| `highlight_css` | String | Syntax highlighting CSS (if enabled) |
| `highlight_js` | String | Syntax highlighting JS (if enabled) |
| `auto_includes_css` | String | Auto-included CSS files |
| `auto_includes_js` | String | Auto-included JS files |
| `auto_includes` | String | All auto-included files |

## Custom Layouts

You can create custom layouts by setting the `layout` front matter:

```markdown
+++
title = "Landing Page"
layout = "landing"
+++

Welcome to our landing page!
```

Create the corresponding template `templates/landing.ecr`:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <title><%= page_title %></title>
  <style>
    /* Landing page specific styles */
  </style>
</head>
<body class="landing">
  <main>
    <%= content %>
  </main>
</body>
</html>
```

## Styling Templates

### Inline Styles

Include CSS directly in your header template:

```erb
<style>
  :root {
    --primary: #e53935;
    --text: #f5f5f5;
    --bg: #0a0a0a;
  }
  body {
    font-family: system-ui, sans-serif;
    color: var(--text);
    background: var(--bg);
  }
</style>
```

### External Stylesheets

Reference CSS files from the `static/` directory:

```erb
<link rel="stylesheet" href="/css/main.css">
```

### Auto Includes

Let Hwaro automatically include CSS files:

1. Configure in `config.toml`:

```toml
[auto_includes]
enabled = true
dirs = ["assets/css"]
```

2. Place CSS files in `static/assets/css/`:

```
static/
└── assets/
    └── css/
        ├── 01-reset.css
        ├── 02-typography.css
        └── 03-layout.css
```

3. Use in your header:

```erb
<%= auto_includes_css %>
```

## Adding JavaScript

### Inline Scripts

```erb
<script>
  // Your JavaScript here
</script>
```

### External Scripts

```erb
<script src="/js/app.js"></script>
```

### Auto Includes for JS

```erb
<%= auto_includes_js %>
```

## Navigation Menus

Build navigation based on your site structure:

```erb
<nav>
  <a href="<%= base_url %>/">Home</a>
  <a href="<%= base_url %>/getting-started/">Getting Started</a>
  <a href="<%= base_url %>/guide/">Guide</a>
  <a href="<%= base_url %>/reference/">Reference</a>
</nav>
```

### Active State

Highlight the current section:

```erb
<nav>
  <a href="<%= base_url %>/guide/"<%= page_section == "guide" ? " class=\"active\"" : "" %>>Guide</a>
</nav>
```

## Responsive Design

Include responsive meta tags and CSS:

```erb
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 0 1rem;
    }
    
    @media (max-width: 768px) {
      .sidebar {
        display: none;
      }
    }
  </style>
</head>
```

## Best Practices

### Keep Templates DRY

Use partials to avoid repetition:

```erb
<!-- templates/nav.ecr -->
<nav class="main-nav">
  <a href="<%= base_url %>/">Home</a>
  <a href="<%= base_url %>/about/">About</a>
</nav>
```

Then include it:

```erb
<%= render "nav" %>
```

### Semantic HTML

Use semantic elements for better accessibility:

```erb
<header>...</header>
<nav>...</nav>
<main>
  <article>...</article>
  <aside>...</aside>
</main>
<footer>...</footer>
```

### Escape User Content

Content from markdown is already escaped, but be careful with custom data.

### Mobile-First

Design for mobile first, then add complexity for larger screens:

```css
/* Base styles (mobile) */
.sidebar { display: none; }

/* Desktop */
@media (min-width: 769px) {
  .sidebar { display: block; }
}
```

## Next Steps

- Learn about [Shortcodes](/guide/shortcodes/) for reusable components
- Explore [Template Variables](/reference/template-variables/) for complete reference
- See [Content Management](/guide/content-management/) for organizing content