+++
title = "Reference"
description = "Technical reference documentation for Hwaro"
toc = true
+++


Complete technical reference documentation for Hwaro. This section provides detailed specifications for CLI commands, configuration options, front matter fields, and template variables.

## Quick Reference

### CLI Commands

| Command | Description |
|---------|-------------|
| `hwaro init` | Create a new Hwaro project |
| `hwaro build` | Build your site to static files |
| `hwaro serve` | Start a local development server |
| `hwaro new` | Create a new content file |

### Essential Configuration

```toml
title = "My Site"
description = "Site description"
base_url = "https://example.com"

[sitemap]
enabled = true

[search]
enabled = true
```

### Basic Front Matter

```markdown
+++
title = "Page Title"
date = "2024-01-15"
description = "Page description"
draft = false
tags = ["tag1", "tag2"]
+++
```

## Reference Documentation

- **[CLI Commands](/reference/cli/)** — Complete documentation for all command-line commands and their options

- **[Configuration](/reference/config/)** — All `config.toml` options with detailed explanations

- **[Front Matter](/reference/front-matter/)** — All front matter fields supported in content files

- **[Template Variables](/reference/template-variables/)** — Variables available in ECR templates

## Quick Links

### Common Tasks

| Task | Reference |
|------|-----------|
| Create a new site | [`hwaro init`](/reference/cli/#hwaro-init) |
| Build for production | [`hwaro build --minify`](/reference/cli/#hwaro-build) |
| Enable search | [`[search]` config](/reference/config/#search) |
| Add social meta tags | [`[og]` config](/reference/config/#opengraph-twitter-cards) |
| Set page description | [`description` front matter](/reference/front-matter/#description) |
| Access page title | [`page_title` variable](/reference/template-variables/#page-variables) |

### Configuration Sections

| Section | Purpose |
|---------|---------|
| `[plugins]` | Content processors |
| `[highlight]` | Syntax highlighting |
| `[search]` | Search index |
| `[sitemap]` | XML sitemap |
| `[robots]` | Robots.txt |
| `[feeds]` | RSS/Atom feeds |
| `[og]` | Social meta tags |
| `[[taxonomies]]` | Content classification |
| `[build]` | Build hooks |
| `[auto_includes]` | Auto CSS/JS |