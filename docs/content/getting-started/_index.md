+++
title = "Overview"
+++

Hwaro (화로) is a fast, lightweight static site generator built with Crystal.

## Features

- **Fast builds** — Parallel processing and smart caching
- **Markdown** — Write content with TOML front matter
- **Jinja2 templates** — Flexible templating with Crinja
- **SEO built-in** — Sitemaps, RSS feeds, meta tags
- **Extensible** — Lifecycle hooks and custom processors

## Where to Start

- Want an end-to-end walkthrough? Start here: [Guide](/guide/)
- Prefer reference docs? Continue with the pages below.

## Quick Start

```bash
# Clone and build
git clone https://github.com/hahwul/hwaro
cd hwaro && shards build --release

# Create a new site
./bin/hwaro init my-site --scaffold docs
cd my-site

# Start development server
hwaro serve
```

Visit `http://localhost:3000` to see your site.

## How It Works

1. **Write** content in `content/` using Markdown
2. **Design** templates in `templates/` using Jinja2
3. **Build** static HTML with `hwaro build`
4. **Deploy** the `public/` folder anywhere

## Next Steps

- [Guide](/guide/) — From zero → deployed (recommended)
- [Installation](/getting-started/installation/) — Install Hwaro
- [CLI Usage](/getting-started/cli/) — Learn the commands
- [Directory Structure](/getting-started/directory-structure/) — Understand the layout
- [Configuration](/getting-started/configuration/) — Configure your site
