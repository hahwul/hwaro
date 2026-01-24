# Docs scaffold - documentation-focused structure
#
# This scaffold creates a documentation site with organized sections,
# sidebar navigation, and documentation-specific templates.

require "./base"

module Hwaro
  module Services
    module Scaffolds
      class Docs < Base
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::Docs
        end

        def description : String
          "Documentation-focused structure with organized sections and sidebar"
        end

        def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {} of String => String

          # Homepage (docs landing)
          files["index.md"] = index_content

          # Getting Started section
          files["getting-started/_index.md"] = getting_started_index
          files["getting-started/installation.md"] = installation_content
          files["getting-started/quick-start.md"] = quick_start_content
          files["getting-started/configuration.md"] = configuration_content

          # Guide section
          files["guide/_index.md"] = guide_index
          files["guide/content-management.md"] = content_management_content
          files["guide/templates.md"] = templates_content
          files["guide/shortcodes.md"] = shortcodes_content

          # API Reference section
          files["reference/_index.md"] = reference_index
          files["reference/cli.md"] = cli_reference_content
          files["reference/config.md"] = config_reference_content

          files
        end

        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {
            "header.html"  => header_template,
            "footer.html"  => footer_template,
            "page.html"    => docs_page_template,
            "section.html" => docs_section_template,
            "404.html"     => not_found_template,
          }

          unless skip_taxonomies
            files["taxonomy.html"] = taxonomy_template
            files["taxonomy_term.html"] = taxonomy_term_template
          end

          files
        end

        def config_content(skip_taxonomies : Bool = false) : String
          config = String.build do |str|
            # Site basics
            str << base_config("Documentation", "Project documentation powered by Hwaro.")

            # Content & Processing
            str << multilingual_config
            str << plugins_config
            str << content_files_config
            str << highlight_config
            str << og_config
            str << search_config
            str << taxonomies_config unless skip_taxonomies

            # SEO & Feeds
            str << sitemap_config
            str << robots_config
            str << llms_config
            str << feeds_config

            # Optional features (commented out by default)
            str << auto_includes_config
            str << markdown_config
            str << build_hooks_config
          end
          config
        end

        # Override header for docs - minimal header integrated with layout (Jinja2 syntax)
        protected def header_template : String
          <<-HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="description" content="{{ page_description }}">
            <title>{{ page_title }} - {{ site_title }}</title>
            {{ og_all_tags }}
            #{styles}
            {{ highlight_css }}
            {{ auto_includes_css }}
          </head>
          <body data-section="{{ page_section }}">
          HTML
        end

        # Override styles for docs - modern unified layout
        protected def styles : String
          <<-CSS
            <style>
              :root {
                --primary: #0070f3;
                --text: #24292f;
                --text-muted: #57606a;
                --border: #d0d7de;
                --bg: #ffffff;
                --bg-subtle: #f6f8fa;
                --header-h: 56px;
                --sidebar-w: 260px;
              }
              *, *::before, *::after { box-sizing: border-box; }
              body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.6; margin: 0; color: var(--text); background: var(--bg); }

              /* Header - fixed top */
              .docs-header { position: fixed; top: 0; left: 0; right: 0; height: var(--header-h); background: var(--bg); border-bottom: 1px solid var(--border); display: flex; align-items: center; padding: 0 1.5rem; z-index: 100; }
              .docs-header .logo { font-weight: 600; font-size: 1.1rem; color: var(--text); text-decoration: none; margin-right: 2rem; }
              .docs-header nav { display: flex; gap: 1.5rem; }
              .docs-header nav a { color: var(--text-muted); text-decoration: none; font-size: 0.9rem; }
              .docs-header nav a:hover { color: var(--primary); }

              /* Layout container */
              .docs-container { display: flex; padding-top: var(--header-h); min-height: 100vh; }

              /* Sidebar - fixed */
              .docs-sidebar { position: fixed; top: var(--header-h); left: 0; width: var(--sidebar-w); height: calc(100vh - var(--header-h)); background: var(--bg-subtle); border-right: 1px solid var(--border); padding: 1.5rem 1rem; overflow-y: auto; }
              .sidebar-section { margin-bottom: 1.5rem; }
              .sidebar-title { font-size: 0.7rem; font-weight: 600; text-transform: uppercase; color: var(--text-muted); margin-bottom: 0.5rem; letter-spacing: 0.05em; padding-left: 0.5rem; }
              .sidebar-links { list-style: none; padding: 0; margin: 0; }
              .sidebar-links li { margin-bottom: 2px; }
              .sidebar-links a { display: block; padding: 0.35rem 0.5rem; color: var(--text-muted); text-decoration: none; border-radius: 4px; font-size: 0.875rem; }
              .sidebar-links a:hover { background: var(--border); color: var(--text); }
              .sidebar-links a.active { background: var(--primary); color: white; }

              /* Main content */
              .docs-main { flex: 1; margin-left: var(--sidebar-w); padding: 2rem 3rem; max-width: 800px; }
              .docs-main h1 { font-size: 1.75rem; margin: 0 0 1.5rem 0; font-weight: 600; }
              .docs-main h2 { font-size: 1.35rem; margin: 2rem 0 1rem 0; padding-bottom: 0.4rem; border-bottom: 1px solid var(--border); }
              .docs-main h3 { font-size: 1.1rem; margin: 1.5rem 0 0.75rem 0; }

              /* Typography */
              code { background: var(--bg-subtle); padding: 0.15rem 0.35rem; border-radius: 4px; font-size: 0.85em; font-family: ui-monospace, "SFMono-Regular", Consolas, monospace; }
              pre { background: var(--bg-subtle); padding: 1rem; border-radius: 6px; overflow-x: auto; border: 1px solid var(--border); }
              pre code { background: none; padding: 0; }
              a { color: var(--primary); text-decoration: none; }
              a:hover { text-decoration: underline; }

              /* Info boxes */
              .info-box { padding: 0.75rem 1rem; border-radius: 6px; margin: 1rem 0; border-left: 3px solid; font-size: 0.9rem; }
              .info-box.note { background: #ddf4ff; border-color: #54aeff; }
              .info-box.warning { background: #fff8c5; border-color: #d4a72c; }
              .info-box.tip { background: #dafbe1; border-color: #4ac26b; }

              /* Section list */
              ul.section-list { list-style: none; padding: 0; }
              ul.section-list li { margin-bottom: 0.5rem; padding: 0.6rem 0.75rem; background: var(--bg-subtle); border-radius: 6px; border: 1px solid var(--border); }
              ul.section-list li a { font-weight: 500; }

              /* Footer */
              .docs-footer { margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid var(--border); color: var(--text-muted); font-size: 0.85rem; }

              /* Responsive */
              @media (max-width: 768px) {
                .docs-sidebar { display: none; }
                .docs-main { margin-left: 0; padding: 1.5rem 1rem; }
              }
            </style>
          CSS
        end

        # Docs-specific page template
        # Override footer for docs (Jinja2 syntax)
        protected def footer_template : String
          <<-HTML
              <div class="docs-footer">
                <p>Powered by Hwaro</p>
              </div>
            </main>
          </div>
          {{ highlight_js }}
          {{ auto_includes_js }}
          </body>
          </html>
          HTML
        end

        # Docs-specific page template (Jinja2 syntax)
        private def docs_page_template : String
          <<-HTML
          {% include "header.html" %}
          <header class="docs-header">
            <a href="{{ base_url }}/" class="logo">{{ site_title }}</a>
            <nav>
              <a href="{{ base_url }}/getting-started/">Getting Started</a>
              <a href="{{ base_url }}/guide/">Guide</a>
              <a href="{{ base_url }}/reference/">Reference</a>
            </nav>
          </header>
          <div class="docs-container">
            <aside class="docs-sidebar">
              <div class="sidebar-section">
                <div class="sidebar-title">Getting Started</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/getting-started/">Overview</a></li>
                  <li><a href="{{ base_url }}/getting-started/installation/">Installation</a></li>
                  <li><a href="{{ base_url }}/getting-started/quick-start/">Quick Start</a></li>
                  <li><a href="{{ base_url }}/getting-started/configuration/">Configuration</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Guide</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/guide/">Overview</a></li>
                  <li><a href="{{ base_url }}/guide/content-management/">Content Management</a></li>
                  <li><a href="{{ base_url }}/guide/templates/">Templates</a></li>
                  <li><a href="{{ base_url }}/guide/shortcodes/">Shortcodes</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Reference</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/reference/">Overview</a></li>
                  <li><a href="{{ base_url }}/reference/cli/">CLI Commands</a></li>
                  <li><a href="{{ base_url }}/reference/config/">Configuration</a></li>
                </ul>
              </div>
            </aside>
            <main class="docs-main">
              <h1>{{ page_title }}</h1>
              {{ content }}
          {% include "footer.html" %}
          HTML
        end

        # Docs-specific section template (Jinja2 syntax)
        private def docs_section_template : String
          <<-HTML
          {% include "header.html" %}
          <header class="docs-header">
            <a href="{{ base_url }}/" class="logo">{{ site_title }}</a>
            <nav>
              <a href="{{ base_url }}/getting-started/">Getting Started</a>
              <a href="{{ base_url }}/guide/">Guide</a>
              <a href="{{ base_url }}/reference/">Reference</a>
            </nav>
          </header>
          <div class="docs-container">
            <aside class="docs-sidebar">
              <div class="sidebar-section">
                <div class="sidebar-title">Getting Started</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/getting-started/">Overview</a></li>
                  <li><a href="{{ base_url }}/getting-started/installation/">Installation</a></li>
                  <li><a href="{{ base_url }}/getting-started/quick-start/">Quick Start</a></li>
                  <li><a href="{{ base_url }}/getting-started/configuration/">Configuration</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Guide</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/guide/">Overview</a></li>
                  <li><a href="{{ base_url }}/guide/content-management/">Content Management</a></li>
                  <li><a href="{{ base_url }}/guide/templates/">Templates</a></li>
                  <li><a href="{{ base_url }}/guide/shortcodes/">Shortcodes</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Reference</div>
                <ul class="sidebar-links">
                  <li><a href="{{ base_url }}/reference/">Overview</a></li>
                  <li><a href="{{ base_url }}/reference/cli/">CLI Commands</a></li>
                  <li><a href="{{ base_url }}/reference/config/">Configuration</a></li>
                </ul>
              </div>
            </aside>
            <main class="docs-main">
              <h1>{{ page_title }}</h1>
              {{ content }}

              <h2>In This Section</h2>
              <ul class="section-list">
                {{ section_list }}
              </ul>
          {% include "footer.html" %}
          HTML
        end

        # Content files
        private def index_content : String
          <<-CONTENT
+++
title = "Documentation"
+++

# Welcome to the Documentation

This documentation site is powered by [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator.

## Quick Links

- **[Getting Started](/getting-started/)** - Installation, setup, and basic usage
- **[Guide](/guide/)** - In-depth guides on content, templates, and more
- **[Reference](/reference/)** - CLI commands and configuration options

## Features

- 📝 Write content in Markdown
- 🎨 Customizable Jinja2 templates
- ⚡ Fast build times with Crystal
- 🔍 Built-in search support
- 📱 Responsive documentation layout
CONTENT
        end

        private def getting_started_index : String
          <<-CONTENT
+++
title = "Getting Started"
+++

# Getting Started

Welcome to the Getting Started guide. This section will help you set up your first Hwaro documentation site.

## What You'll Learn

1. How to install Hwaro
2. Creating your first documentation site
3. Basic configuration options
4. Building and previewing your site
CONTENT
        end

        private def installation_content : String
          <<-CONTENT
+++
title = "Installation"
+++

# Installation

Learn how to install Hwaro on your system.

## Prerequisites

- [Crystal](https://crystal-lang.org/) 1.0 or later
- Git (optional, for cloning)

## Install from Source

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards install
shards build --release
```

## Verify Installation

```bash
./bin/hwaro --version
```

You should see the version number if Hwaro is installed correctly.

## Next Steps

Once installed, proceed to the [Quick Start](/getting-started/quick-start.html) guide.
CONTENT
        end

        private def quick_start_content : String
          <<-CONTENT
+++
title = "Quick Start"
+++

# Quick Start

Get up and running with Hwaro in minutes.

## Create a New Project

```bash
hwaro init my-docs --scaffold docs
cd my-docs
```

## Project Structure

```
my-docs/
├── config.toml          # Site configuration
├── content/             # Markdown content files
│   ├── index.md
│   ├── getting-started/
│   └── guide/
├── templates/           # Jinja2 templates
└── static/              # Static assets
```

## Build Your Site

```bash
hwaro build
```

The generated site will be in the `public/` directory.

## Preview Locally

```bash
hwaro serve
```

Visit `http://localhost:3000` to see your site.

## Next Steps

- Read about [Configuration](/getting-started/configuration.html)
- Learn about [Content Management](/guide/content-management.html)
CONTENT
        end

        private def configuration_content : String
          <<-CONTENT
+++
title = "Configuration"
+++

# Configuration

Hwaro is configured through a `config.toml` file in your project root.

## Basic Configuration

```toml
title = "My Documentation"
description = "Project documentation"
base_url = "https://docs.example.com"
```

## Search Configuration

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content"]
```

## SEO Configuration

```toml
[sitemap]
enabled = true

[robots]
enabled = true
```

## Full Reference

See the [Configuration Reference](/reference/config.html) for all available options.
CONTENT
        end

        private def guide_index : String
          <<-CONTENT
+++
title = "Guide"
+++

# Guide

This section contains in-depth guides for using Hwaro effectively.

## Topics

Learn about the core concepts and features of Hwaro:

- **Content Management** - Organize and write your documentation
- **Templates** - Customize the look and feel of your site
- **Shortcodes** - Add reusable components to your content
CONTENT
        end

        private def content_management_content : String
          <<-CONTENT
+++
title = "Content Management"
+++

# Content Management

Learn how to organize and write content in Hwaro.

## Content Directory

All content files live in the `content/` directory:

```
content/
├── index.md              # Homepage
├── getting-started/      # Section
│   ├── _index.md         # Section index
│   ├── installation.md   # Page
│   └── quick-start.md    # Page
└── guide/
    └── ...
```

## Front Matter

Each content file starts with front matter in TOML format:

```markdown
+++
title = "Page Title"
date = "2024-01-01"
description = "Page description for SEO"
+++

# Your Content Here
```

## Sections

Sections are directories containing related content. Each section should have an `_index.md` file.

## Links

Link to other pages using relative paths:

```markdown
[Installation](/getting-started/installation.html)
```

## Images

Place images in `static/` and reference them:

```markdown
![Diagram](/images/diagram.png)
```
CONTENT
        end

        private def templates_content : String
          <<-CONTENT
+++
title = "Templates"
+++

# Templates

Hwaro uses Jinja2-compatible templates (via Crinja) for rendering pages.

## Template Directory

Templates are stored in `templates/`:

```
templates/
├── base.html       # Base template with common structure
├── page.html       # Regular pages
├── section.html    # Section indexes
├── partials/       # Partial templates
│   └── nav.html
└── shortcodes/     # Shortcode templates
```

## Available Variables

In templates, you have access to:

| Variable | Description |
|----------|-------------|
| `page_title` | Current page title |
| `site_title` | Site title from config |
| `content` | Rendered page content |
| `base_url` | Site base URL |

## Template Inheritance

Extend base templates:

```jinja
{% extends "base.html" %}
{% block content %}{{ content }}{% endblock %}
```

## Including Partials

Include other templates:

```jinja
{% include "partials/nav.html" %}
```

## Customization

Modify templates to change the site layout, add navigation, or include custom scripts.
CONTENT
        end

        private def shortcodes_content : String
          <<-CONTENT
+++
title = "Shortcodes"
+++

# Shortcodes

Shortcodes are reusable content snippets you can embed in your Markdown.

## Using Shortcodes

In your Markdown content:

```jinja
{{ alert(type="info", message="This is an info alert") }}
```

## Built-in Shortcodes

### Alert

Display an alert box:

```jinja
{{ alert(type="warning", message="Be careful!") }}
```

Types: `info`, `warning`, `tip`, `note`

## Creating Custom Shortcodes

1. Create a template in `templates/shortcodes/`:

```jinja
{# templates/shortcodes/highlight.html #}
<mark class="highlight">{{ text }}</mark>
```

2. Use it in your content:

```jinja
{{ highlight(text="Important text here") }}
```

## Advanced Example

```jinja
{# templates/shortcodes/alert.html #}
{% if type and message %}
<div class="alert alert-{{ type }}">
  {{ message | safe }}
</div>
{% endif %}
```

## Best Practices

- Keep shortcodes simple and focused
- Document your custom shortcodes
- Use semantic HTML in shortcode templates
- Use the `safe` filter for HTML content
CONTENT
        end

        private def reference_index : String
          <<-CONTENT
+++
title = "Reference"
+++

# Reference

Technical reference documentation for Hwaro.

## Contents

- **CLI Commands** - All available command-line commands
- **Configuration** - Complete configuration options reference
CONTENT
        end

        private def cli_reference_content : String
          <<-CONTENT
+++
title = "CLI Commands"
+++

# CLI Commands

Reference for all Hwaro command-line commands.

## hwaro init

Initialize a new Hwaro project.

```bash
hwaro init [path] [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--scaffold TYPE` | Scaffold type: simple, blog, docs (default: simple) |
| `--force` | Overwrite existing files |
| `--skip-sample-content` | Don't create sample content |

**Examples:**

```bash
hwaro init my-site
hwaro init my-blog --scaffold blog
hwaro init my-docs --scaffold docs --force
```

## hwaro build

Build the static site.

```bash
hwaro build [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--config FILE` | Use a custom config file |
| `--output DIR` | Output directory (default: public) |

## hwaro serve

Start a development server.

```bash
hwaro serve [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--port PORT` | Server port (default: 3000) |
| `--host HOST` | Server host (default: localhost) |

## hwaro new

Create a new content file.

```bash
hwaro new [path]
```

Creates a new Markdown file with front matter template.
CONTENT
        end

        private def config_reference_content : String
          <<-CONTENT
+++
title = "Configuration Reference"
+++

# Configuration Reference

Complete reference for `config.toml` options.

## Site Settings

```toml
title = "Site Title"
description = "Site description"
base_url = "https://example.com"
```

| Key | Type | Description |
|-----|------|-------------|
| `title` | string | Site title |
| `description` | string | Site description |
| `base_url` | string | Production URL |

## Search

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content"]
filename = "search.json"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | false | Enable search index |
| `format` | string | "fuse_json" | Index format |
| `fields` | array | ["title"] | Fields to index |

## Sitemap

```toml
[sitemap]
enabled = true
filename = "sitemap.xml"
changefreq = "weekly"
priority = 0.5
```

## RSS/Atom Feeds

```toml
[feeds]
enabled = true
type = "rss"
limit = 10
sections = ["posts"]
```

## Taxonomies

```toml
[[taxonomies]]
name = "tags"
feed = true

[[taxonomies]]
name = "categories"
paginate_by = 10
```
CONTENT
        end
      end
    end
  end
end
