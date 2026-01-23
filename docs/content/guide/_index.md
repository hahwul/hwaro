+++
title = "Guide"
description = "In-depth guides for using Hwaro effectively"
+++


This section contains comprehensive guides for using Hwaro to build your static sites. Whether you're creating documentation, a blog, or a portfolio, these guides will help you understand Hwaro's features in depth.

## Core Concepts

Hwaro follows a simple but powerful architecture:

1. **Content** — Write in Markdown with TOML front matter
2. **Templates** — Design with ECR (Embedded Crystal) templates
3. **Build** — Transform content into static HTML files
4. **Deploy** — Host the generated files anywhere

## Available Guides

### Content & Structure

- **[Content Management](/guide/content-management/)** — Organize and author your content with Markdown, front matter, sections, and assets

- **[Templates](/guide/templates/)** — Create and customize ECR templates, partials, and layouts

- **[Shortcodes](/guide/shortcodes/)** — Build reusable content components for your Markdown files

### Organization

- **[Taxonomies](/guide/taxonomies/)** — Categorize content with tags, categories, and custom taxonomies

### Discovery

- **[SEO Features](/guide/seo/)** — Optimize for search engines with sitemaps, meta tags, RSS feeds, and more

- **[Search](/guide/search/)** — Add client-side search functionality to your site

## Quick Tips

### Write Content Fast

```markdown
+++
title = "My Post"
tags = ["tutorial", "beginner"]
+++


Write your content in **Markdown** with full formatting support.
```

### Customize Everything

Templates give you complete control over your site's HTML:

```erb
<article>
  <h1><%= page_title %></h1>
  <div class="content">
    <%= content %>
  </div>
</article>
```

### Build & Preview

```bash
hwaro serve

hwaro build --minify
```

## Need Help?

- Check the [Reference](/reference/) for complete API documentation
- Report issues on [GitHub](https://github.com/hahwul/hwaro/issues)