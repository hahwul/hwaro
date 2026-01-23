+++
title = "Quick Start"
description = "Get up and running with Hwaro in minutes"
toc = true
+++


This guide will walk you through creating your first Hwaro site in just a few minutes.

## Create a New Project

Use the `init` command to create a new Hwaro project:

```bash
hwaro init my-site
```

This creates a basic site structure. For more specialized setups, use the `--scaffold` option:

```bash
hwaro init my-docs --scaffold docs

hwaro init my-blog --scaffold blog

hwaro init my-site --scaffold simple
```

## Project Structure

After initialization, your project will have this structure:

```
my-site/
├── config.toml          # Site configuration
├── content/             # Markdown content files
│   ├── index.md         # Homepage
│   └── ...
├── templates/           # ECR templates
│   ├── header.ecr       # Common header partial
│   ├── footer.ecr       # Common footer partial
│   ├── page.ecr         # Regular page template
│   └── section.ecr      # Section index template
└── static/              # Static assets (CSS, JS, images)
```

## Understanding the Files

### config.toml

The main configuration file for your site:

```toml
title = "My Site"
description = "Welcome to my site"
base_url = "https://example.com"

[search]
enabled = true

[sitemap]
enabled = true
```

### Content Files

Content is written in Markdown with TOML front matter:

```markdown
+++
title = "My First Post"
date = "2024-01-15"
description = "This is my first post"
+++


This is my first post written in **Markdown**.
```

### Templates

Templates use ECR (Embedded Crystal) syntax:

```erb
<!DOCTYPE html>
<html>
<head>
  <title><%= page_title %> - <%= site_title %></title>
</head>
<body>
  <main>
    <%= content %>
  </main>
</body>
</html>
```

## Build Your Site

Generate the static site with the `build` command:

```bash
cd my-site
hwaro build
```

The generated files will be in the `public/` directory.

### Build Options

Customize the build with various options:

```bash
hwaro build --minify

hwaro build --drafts

hwaro build --output-dir dist

hwaro build --cache

hwaro build --verbose
```

## Preview Locally

Start a local development server:

```bash
hwaro serve
```

Your site will be available at `http://localhost:3000`.

### Server Options

```bash
hwaro serve --port 8080

hwaro serve --bind 127.0.0.1

hwaro serve --open
```

The development server automatically rebuilds your site when files change.

## Create New Content

Use the `new` command to create content files:

```bash
hwaro new content/about.md

hwaro new content/blog/my-first-post.md
```

This creates a new file with front matter template:

```markdown
+++
title = "My First Post"
date = "2024-01-15"
draft = true
+++

Write your content here...
```

## Adding Sections

Create organized content sections by adding directories:

```bash
mkdir -p content/blog
```

Then add an `_index.md` for the section:

```markdown
+++
title = "Blog"
+++


Welcome to my blog.
```

Add posts to the section:

```markdown
+++
title = "Hello World"
date = "2024-01-15"
+++


My first blog post.
```

## Next Steps

Now that you have a basic site running:

1. **[Configure your site](/getting-started/configuration/)** — Customize settings in `config.toml`
2. **[Manage content](/guide/content-management/)** — Learn about content organization
3. **[Customize templates](/guide/templates/)** — Design your site's look
4. **[Add SEO features](/guide/seo/)** — Enable sitemaps, feeds, and meta tags

## Example Workflow

Here's a typical development workflow:

```bash
hwaro serve

hwaro new content/blog/new-post.md

# The server auto-rebuilds on changes

hwaro build --minify

```
