<div align="center">
  <img alt="Hwaro Logo" src="docs/static/hwaro-wide.webp" width="500px;">
  <p>A lightweight and fast static site generator written in Crystal.</p>
</div>

<p align="center">
<a href="https://github.com/hahwul/hwaro/blob/main/CONTRIBUTING.md">
<img src="https://img.shields.io/badge/CONTRIBUTIONS-WELCOME-000000?style=for-the-badge&labelColor=black"></a>
<a href="https://github.com/hahwul/hwaro/releases">
<img src="https://img.shields.io/github/v/release/hahwul/hwaro?style=for-the-badge&color=black&labelColor=black&logo=web"></a>
<a href="https://crystal-lang.org">
<img src="https://img.shields.io/badge/Crystal-000000?style=for-the-badge&logo=crystal&logoColor=white"></a>
</p>

<p align="center">
  <a href="https://hwaro.hahwul.com/start/">Documentation</a> •
  <a href="https://hwaro.hahwul.com/start/installation/">Installation</a> •
  <a href="https://hwaro.hahwul.com/deploy/github-pages/">Github Action</a> •
  <a href="#contributing">Contributing</a> •
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

Hwaro processes Markdown content with TOML front matter and Jinja2-compatible templates (Crinja) to build high-performance static sites. It features parallel builds, incremental caching, and a built-in dev server with live reload.

<details>
<summary><strong>Features</strong></summary>

### Content & Templating
- Markdown with TOML/YAML front matter
- Jinja2 templates (inheritance, includes, macros)
- Markdown extensions: task lists, footnotes, definition lists, math (KaTeX/MathJax), Mermaid diagrams, emoji, etc
- Built-in shortcodes (YouTube, Vimeo, Gist, Alert, Figure, Tweet, CodePen) and custom shortcode support
- Syntax highlighting via Highlight.js
- Table of contents (TOC) generation
- Reading time and word count
- Content summaries via `<!-- more -->` marker
- Non-markdown content file publishing

### Content Management
- Draft, scheduled, and expiring post support
- URL aliases and redirects
- Archetypes for content scaffolding templates
- Data files (YAML, JSON, TOML) accessible in templates
- Author data aggregation and management
- Page weight and custom sorting (by date, weight, title)

### Build & Performance
- Parallel processing and incremental build caching
- Streaming build mode with memory limits
- Pre/post build hooks
- CSS/JS bundling, minification, and content-hash fingerprinting
- Lazy loading images
- Environment-specific config (`config.production.toml`, `config.staging.toml`, etc.)

### SEO & Discovery
- Auto-generated sitemap, robots.txt, RSS/Atom feeds
- OpenGraph meta tags and auto-generated OG images (PNG)
- Twitter Cards and JSON-LD structured data (Article, FAQ, HowTo, Organization, Person)
- Canonical URLs and hreflang tags
- `llms.txt` and `AGENTS.md` generation
- Client-side search index (Fuse.js, ElasticLunr) with CJK tokenization

### Site Features
- Pagination, taxonomies (tags, categories, custom)
- Content series and related posts
- Breadcrumb navigation and previous/next page links
- Multilingual (i18n) with per-language feeds and search
- Image processing (resize, responsive images, LQIP blur-up placeholders, dominant color extraction) and auto-generated OG images
- PWA support (manifest, service worker)
- AMP page generation
- Transparent sections for flexible content organization

### Development & Deployment
- Dev server with live reload and error overlay
- Scaffolding with built-in themes (`blog`, `docs`, `blog-dark`, `docs-dark`)
- Deploy to multiple targets with dry-run support
- Platform config generation (Netlify, Vercel, Cloudflare Pages)
- GitHub Actions CI/CD generation
- Import from WordPress, Jekyll, Hugo
- Link checker, config doctor, and front matter format conversion

</details>

## Installation

### Homebrew

```bash
brew tap hahwul/hwaro
brew install hwaro
```

### From source

```bash
# Clone the repository
git clone https://github.com/hahwul/hwaro.git
cd hwaro

# Install dependencies
shards install

# Build
shards build --release --no-debug --production
```

> For more installation options including Docker and pre-built binaries, see the [Installation Guide](https://hwaro.hahwul.com/start/installation/).

## Contributing

Hwaro is an open-source project made with ❤️. If you would like to contribute, please check [CONTRIBUTING.md](CONTRIBUTING.md) and submit a Pull Request.

![](docs/static/CONTRIBUTORS.svg)

## Why "Hwaro"?

Hwaro (화로) is the Korean word for **Furnace** — the same name used in Minecraft's Korean localization. In the game, the Furnace is an essential tool that transforms raw materials into useful items. Hwaro aims to serve the same role for static sites: feed in your content, and it crafts a complete website.
