+++
title = "Template Variables"
description = "Complete reference for all variables available in ECR templates"
toc = true
+++


This is the complete reference for all variables available in Hwaro's ECR templates. These variables can be used in your template files using the `<%= variable_name %>` syntax.

## Site Variables

Variables containing site-wide information from `config.toml`.

- `site_title` (String): Site title from configuration
- `site_description` (String): Site description from configuration
- `base_url` (String): Base URL from configuration (no trailing slash)

### Example Usage

```erb
<title><%= page_title %> - <%= site_title %></title>
<meta name="description" content="<%= site_description %>">
<link rel="canonical" href="<%= base_url %><%= page_url %>">
```

## Page Variables

Variables containing information about the current page.

- `page_title` (String): Current page title from front matter
- `page_description` (String): Page description (falls back to `site_description`)
- `page_url` (String): Current page URL path (e.g., `/getting-started/`)
- `page_section` (String): Section the page belongs to (e.g., `getting-started`)
- `page_image` (String): Page image URL from front matter
- `content` (String): Rendered page content (HTML)

### Example Usage

```erb
<article>
  <h1><%= page_title %></h1>
  
  <% if page_description != "" %>
    <p class="lead"><%= page_description %></p>
  <% end %>
  
  <div class="content">
    <%= content %>
  </div>
</article>
```

### Page URL Examples

- `content/index.md` → `page_url` = `/`
- `content/about.md` → `page_url` = `/about/`
- `content/blog/_index.md` → `page_url` = `/blog/`
- `content/blog/my-post.md` → `page_url` = `/blog/my-post/`
- `content/docs/guide/intro.md` → `page_url` = `/docs/guide/intro/`

### Page Section Examples

- `content/index.md` → `page_section` = `""` (empty)
- `content/about.md` → `page_section` = `""` (empty)
- `content/blog/_index.md` → `page_section` = `blog`
- `content/blog/my-post.md` → `page_section` = `blog`
- `content/docs/guide/intro.md` → `page_section` = `docs`

## Section Variables

Variables available in section templates (`section.ecr`).

- `section_list` (String): HTML list of pages in the section

### Example Usage

```erb
<h2>Pages in This Section</h2>
<ul class="section-pages">
  <%= section_list %>
</ul>
```

### Section List Output

The `section_list` variable generates HTML list items:

```html
<li><a href="/getting-started/installation/">Installation</a></li>
<li><a href="/getting-started/quick-start/">Quick Start</a></li>
<li><a href="/getting-started/configuration/">Configuration</a></li>
```

## SEO & Meta Tag Variables

Variables for SEO and social sharing meta tags.

- `og_tags` (String): OpenGraph meta tags
- `twitter_tags` (String): Twitter Card meta tags
- `og_all_tags` (String): Combined OpenGraph and Twitter tags

### Example Usage

```erb
<head>
  <meta charset="UTF-8">
  <title><%= page_title %> - <%= site_title %></title>
  <meta name="description" content="<%= page_description %>">
  
  <!-- Social sharing meta tags -->
  <%= og_all_tags %>
</head>
```

### Generated Output

When using `<%= og_all_tags %>`:

```html
<meta property="og:title" content="Installation Guide">
<meta property="og:type" content="article">
<meta property="og:url" content="https://example.com/getting-started/installation/">
<meta property="og:description" content="Learn how to install Hwaro">
<meta property="og:image" content="https://example.com/images/og-default.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Installation Guide">
<meta name="twitter:description" content="Learn how to install Hwaro">
<meta name="twitter:image" content="https://example.com/images/og-default.png">
<meta name="twitter:site" content="@yourusername">
```

## Asset Variables

Variables for including CSS, JavaScript, and other assets.

- `highlight_css` (String): Syntax highlighting CSS (if enabled)
- `highlight_js` (String): Syntax highlighting JavaScript (if enabled)
- `auto_includes_css` (String): Auto-included CSS `<link>` tags
- `auto_includes_js` (String): Auto-included JS `<script>` tags
- `auto_includes` (String): All auto-included CSS and JS tags

### Example Usage

```erb
<head>
  <!-- Other head content -->
  
  <!-- Syntax highlighting CSS -->
  <%= highlight_css %>
  
  <!-- Auto-included CSS files -->
  <%= auto_includes_css %>
</head>
<body>
  <!-- Page content -->
  
  <!-- Syntax highlighting JavaScript -->
  <%= highlight_js %>
  
  <!-- Auto-included JavaScript files -->
  <%= auto_includes_js %>
</body>
```

### highlight_css Output

When syntax highlighting is enabled:

```html
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
```

### highlight_js Output

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script>hljs.highlightAll();</script>
```

### auto_includes_css Output

For files in `static/assets/css/`:

```html
<link rel="stylesheet" href="/assets/css/01-reset.css">
<link rel="stylesheet" href="/assets/css/02-typography.css">
<link rel="stylesheet" href="/assets/css/03-layout.css">
```

### auto_includes_js Output

For files in `static/assets/js/`:

```html
<script src="/assets/js/01-utils.js"></script>
<script src="/assets/js/02-app.js"></script>
```

## Template Rendering

### render

Include another template file.

```erb
<%= render "partial_name" %>
```

The partial name is relative to the `templates/` directory, without the `.ecr` extension.

### Example

```erb
<!-- templates/page.ecr -->
<%= render "header" %>
<main>
  <h1><%= page_title %></h1>
  <%= content %>
</main>
<%= render "footer" %>
```

This includes `templates/header.ecr` and `templates/footer.ecr`.

## Conditional Rendering

Use Crystal control structures for conditional content.

### Basic Conditionals

```erb
<% if page_description != "" %>
  <meta name="description" content="<%= page_description %>">
<% end %>
```

### Section-Based Styling

```erb
<body class="<%= page_section %>">
```

### Active Navigation

```erb
<nav>
  <a href="<%= base_url %>/getting-started/"<%= page_section == "getting-started" ? " class=\"active\"" : "" %>>
    Getting Started
  </a>
  <a href="<%= base_url %>/guide/"<%= page_section == "guide" ? " class=\"active\"" : "" %>>
    Guide
  </a>
</nav>
```

### Current Page Highlighting

```erb
<a href="<%= base_url %>/about/"<%= page_url == "/about/" ? " class=\"active\"" : "" %>>
  About
</a>
```

## Common Patterns

### Full HTML Document Structure

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
</head>
<body data-section="<%= page_section %>">
  <header>
    <a href="<%= base_url %>/" class="logo"><%= site_title %></a>
  </header>
  
  <main>
    <h1><%= page_title %></h1>
    <%= content %>
  </main>
  
  <footer>
    <p>&copy; 2024 <%= site_title %></p>
  </footer>
  
  <%= highlight_js %>
  <%= auto_includes_js %>
</body>
</html>
```

### Header/Footer Partial Pattern

**templates/header.ecr:**

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
</head>
<body>
```

**templates/footer.ecr:**

```erb
  <footer>
    <p>Built with Hwaro</p>
  </footer>
  <%= highlight_js %>
  <%= auto_includes_js %>
</body>
</html>
```

**templates/page.ecr:**

```erb
<%= render "header" %>
<main>
  <article>
    <h1><%= page_title %></h1>
    <%= content %>
  </article>
</main>
<%= render "footer" %>
```

### Canonical URL

```erb
<link rel="canonical" href="<%= base_url %><%= page_url %>">
```

### RSS Feed Link

```erb
<link rel="alternate" type="application/rss+xml" title="RSS Feed" href="<%= base_url %>/rss.xml">
```

### JSON-LD Structured Data

```erb
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "<%= page_title %>",
  "description": "<%= page_description %>",
  "url": "<%= base_url %><%= page_url %>"
}
</script>
```

## Variable Availability by Template

All variables are available in all template types unless noted otherwise:

**Available in all templates:**

- `site_title`, `site_description`, `base_url`
- `page_title`, `page_description`, `page_url`, `page_section`, `page_image`
- `content`
- `og_tags`, `twitter_tags`, `og_all_tags`
- `highlight_css`, `highlight_js`
- `auto_includes_css`, `auto_includes_js`, `auto_includes`

**Section-specific:**

- `section_list` — Only available in `section.ecr`

## See Also

- [Templates Guide](/guide/templates/) — Introduction to ECR templates
- [Configuration Reference](/reference/config/) — Configure site variables
- [Front Matter Reference](/reference/front-matter/) — Set page variables
