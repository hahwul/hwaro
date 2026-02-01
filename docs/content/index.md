+++
title = "Hwaro Documentation"
+++

Hwaro(화로) is a fast, lightweight static site generator built with Crystal.

## Features

- **Fast builds** — Parallel processing with smart caching
- **Markdown content** — Write with TOML front matter
- **Jinja2 templates** — Flexible templating with Crinja
- **SEO built-in** — Sitemaps, RSS feeds, OpenGraph tags
- **Extensible** — Lifecycle hooks and custom processors

## Quick Start

```bash
# Install
git clone https://github.com/hahwul/hwaro
cd hwaro && shards build --release

# Create site
./bin/hwaro init my-site --scaffold blog
cd my-site

# Start server
hwaro serve
```

Open `http://localhost:3000` to preview your site.

## Documentation

<div class="doc-grid">

### [Start](/start/)
Installation, first site, CLI commands, and configuration.

### [Writing](/writing/)
Pages, sections, taxonomies, and shortcodes.

### [Templates](/templates/)
Data model, syntax, functions, and filters.

### [Features](/features/)
SEO, search, syntax highlighting, and pagination.

### [Deploy](/deploy/)
Build and deploy to GitHub Pages and other hosts.

</div>

## How It Works

```
content/           →   public/
├── index.md            ├── index.html
├── about.md            ├── about/index.html
└── blog/               └── blog/
    ├── _index.md           ├── index.html
    └── post.md             └── post/index.html
```

1. Write content in `content/` using Markdown
2. Design templates in `templates/` using Jinja2
3. Build with `hwaro build`
4. Deploy `public/` anywhere