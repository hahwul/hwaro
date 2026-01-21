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
            "header.ecr"  => header_template,
            "footer.ecr"  => footer_template,
            "page.ecr"    => docs_page_template,
            "section.ecr" => docs_section_template,
            "404.ecr"     => not_found_template,
          }

          unless skip_taxonomies
            files["taxonomy.ecr"] = taxonomy_template
            files["taxonomy_term.ecr"] = taxonomy_term_template
          end

          files
        end

        def config_content(skip_taxonomies : Bool = false) : String
          config = String.build do |str|
            # Site basics
            str << base_config("Documentation", "Project documentation powered by Hwaro.")

            # Content & Processing
            str << plugins_config
            str << highlight_config
            str << search_config
            str << taxonomies_config unless skip_taxonomies

            # SEO & Feeds
            str << sitemap_config
            str << robots_config
            str << llms_config
            str << feeds_config

            # Optional features (commented out by default)
            str << auto_includes_config
            str << build_hooks_config
          end
          config
        end

        # Override navigation for docs
        protected def navigation : String
          <<-NAV
              <nav>
                <a href="<%= base_url %>/">Home</a>
                <a href="<%= base_url %>/getting-started/">Getting Started</a>
                <a href="<%= base_url %>/guide/">Guide</a>
                <a href="<%= base_url %>/reference/">Reference</a>
              </nav>
          NAV
        end

        # Override styles for docs
        protected def styles : String
          <<-CSS
            <style>
              :root {
                --primary-color: #0070f3;
                --secondary-color: #7928ca;
                --text-color: #333;
                --text-muted: #666;
                --border-color: #eaeaea;
                --bg-code: #f6f8fa;
                --bg-sidebar: #fafbfc;
              }
              * { box-sizing: border-box; }
              body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.7; margin: 0; padding: 0; color: var(--text-color); }
              .docs-layout { display: flex; min-height: 100vh; }
              .docs-sidebar { width: 260px; background: var(--bg-sidebar); border-right: 1px solid var(--border-color); padding: 1.5rem; position: fixed; height: 100vh; overflow-y: auto; }
              .docs-main { flex: 1; margin-left: 260px; padding: 2rem 3rem; max-width: 900px; }
              header { margin-bottom: 2rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border-color); }
              h1, h2, h3, h4 { line-height: 1.3; margin-top: 1.5em; }
              h1 { font-size: 2rem; margin-top: 0; }
              h2 { font-size: 1.5rem; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
              h3 { font-size: 1.25rem; }
              nav a { margin-right: 1.5rem; text-decoration: none; color: var(--primary-color); font-weight: 500; }
              nav a:hover { text-decoration: underline; }
              footer { margin-top: 3rem; border-top: 1px solid var(--border-color); padding-top: 1rem; color: var(--text-muted); font-size: 0.9rem; }
              code { background: var(--bg-code); padding: 0.2rem 0.4rem; border-radius: 3px; font-size: 0.9em; font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; }
              pre { background: var(--bg-code); padding: 1rem; border-radius: 6px; overflow-x: auto; border: 1px solid var(--border-color); }
              pre code { background: none; padding: 0; }
              a { color: var(--primary-color); }
              a:hover { text-decoration: underline; }
              /* Sidebar styles */
              .sidebar-section { margin-bottom: 1.5rem; }
              .sidebar-title { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; color: var(--text-muted); margin-bottom: 0.5rem; letter-spacing: 0.05em; }
              .sidebar-links { list-style: none; padding: 0; margin: 0; }
              .sidebar-links li { margin-bottom: 0.25rem; }
              .sidebar-links a { display: block; padding: 0.3rem 0.5rem; color: var(--text-color); text-decoration: none; border-radius: 4px; font-size: 0.9rem; }
              .sidebar-links a:hover { background: var(--border-color); color: var(--primary-color); }
              .sidebar-links a.active { background: var(--primary-color); color: white; }
              /* Table of contents */
              .toc { background: var(--bg-sidebar); border: 1px solid var(--border-color); border-radius: 6px; padding: 1rem; margin: 1.5rem 0; }
              .toc-title { font-weight: 600; margin-bottom: 0.5rem; }
              .toc ul { margin: 0; padding-left: 1.5rem; }
              .toc li { margin-bottom: 0.25rem; }
              /* Info boxes */
              .info-box { padding: 1rem; border-radius: 6px; margin: 1rem 0; border-left: 4px solid; }
              .info-box.note { background: #e7f5ff; border-color: #1c7ed6; }
              .info-box.warning { background: #fff3bf; border-color: #f59f00; }
              .info-box.tip { background: #d3f9d8; border-color: #37b24d; }
              /* Section list */
              ul.section-list { list-style: none; padding: 0; }
              ul.section-list li { margin-bottom: 0.75rem; padding: 0.75rem; background: var(--bg-sidebar); border-radius: 6px; border: 1px solid var(--border-color); }
              ul.section-list li a { font-weight: 500; }
              /* Responsive */
              @media (max-width: 768px) {
                .docs-sidebar { display: none; }
                .docs-main { margin-left: 0; padding: 1rem; }
              }
            </style>
          CSS
        end

        # Docs-specific page template
        private def docs_page_template : String
          <<-HTML
          <%= render "header" %>
          <div class="docs-layout">
            <aside class="docs-sidebar">
              <div class="sidebar-section">
                <div class="sidebar-title">Getting Started</div>
                <ul class="sidebar-links">
                  <li><a href="<%= base_url %>/getting-started/">Overview</a></li>
                  <li><a href="<%= base_url %>/getting-started/installation.html">Installation</a></li>
                  <li><a href="<%= base_url %>/getting-started/quick-start.html">Quick Start</a></li>
                  <li><a href="<%= base_url %>/getting-started/configuration.html">Configuration</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Guide</div>
                <ul class="sidebar-links">
                  <li><a href="<%= base_url %>/guide/">Overview</a></li>
                  <li><a href="<%= base_url %>/guide/content-management.html">Content Management</a></li>
                  <li><a href="<%= base_url %>/guide/templates.html">Templates</a></li>
                  <li><a href="<%= base_url %>/guide/shortcodes.html">Shortcodes</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Reference</div>
                <ul class="sidebar-links">
                  <li><a href="<%= base_url %>/reference/">Overview</a></li>
                  <li><a href="<%= base_url %>/reference/cli.html">CLI Commands</a></li>
                  <li><a href="<%= base_url %>/reference/config.html">Configuration</a></li>
                </ul>
              </div>
            </aside>
            <main class="docs-main">
              <h1><%= page_title %></h1>
              <%= content %>
            </main>
          </div>
          <%= render "footer" %>
          HTML
        end

        # Docs-specific section template
        private def docs_section_template : String
          <<-HTML
          <%= render "header" %>
          <div class="docs-layout">
            <aside class="docs-sidebar">
              <div class="sidebar-section">
                <div class="sidebar-title">Getting Started</div>
                <ul class="sidebar-links">
                  <li><a href="<%= base_url %>/getting-started/">Overview</a></li>
                  <li><a href="<%= base_url %>/getting-started/installation.html">Installation</a></li>
                  <li><a href="<%= base_url %>/getting-started/quick-start.html">Quick Start</a></li>
                  <li><a href="<%= base_url %>/getting-started/configuration.html">Configuration</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Guide</div>
                <ul class="sidebar-links">
                  <li><a href="<%= base_url %>/guide/">Overview</a></li>
                  <li><a href="<%= base_url %>/guide/content-management.html">Content Management</a></li>
                  <li><a href="<%= base_url %>/guide/templates.html">Templates</a></li>
                  <li><a href="<%= base_url %>/guide/shortcodes.html">Shortcodes</a></li>
                </ul>
              </div>
              <div class="sidebar-section">
                <div class="sidebar-title">Reference</div>
                <ul class="sidebar-links">
                  <li><a href="<%= base_url %>/reference/">Overview</a></li>
                  <li><a href="<%= base_url %>/reference/cli.html">CLI Commands</a></li>
                  <li><a href="<%= base_url %>/reference/config.html">Configuration</a></li>
                </ul>
              </div>
            </aside>
            <main class="docs-main">
              <h1><%= page_title %></h1>
              <%= content %>

              <h2>In This Section</h2>
              <ul class="section-list">
                <%= section_list %>
              </ul>
            </main>
          </div>
          <%= render "footer" %>
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
- 🎨 Customizable templates with ECR
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
├── templates/           # ECR templates
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

Hwaro uses ECR (Embedded Crystal) templates for rendering pages.

## Template Directory

Templates are stored in `templates/`:

```
templates/
├── header.ecr    # Common header
├── footer.ecr    # Common footer
├── page.ecr      # Regular pages
├── section.ecr   # Section indexes
└── shortcodes/   # Shortcode templates
```

## Available Variables

In templates, you have access to:

| Variable | Description |
|----------|-------------|
| `page_title` | Current page title |
| `site_title` | Site title from config |
| `content` | Rendered page content |
| `base_url` | Site base URL |

## Including Partials

Include other templates:

```erb
<%= render "header" %>
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

```markdown
{{< alert type="info" message="This is an info alert" >}}
```

## Built-in Shortcodes

### Alert

Display an alert box:

```markdown
{{< alert type="warning" message="Be careful!" >}}
```

Types: `info`, `warning`, `tip`, `note`

## Creating Custom Shortcodes

1. Create a template in `templates/shortcodes/`:

```erb
<!-- templates/shortcodes/myshortcode.ecr -->
<div class="my-shortcode">
  <%= content %>
</div>
```

2. Use it in your content:

```markdown
{{< myshortcode >}}
Content here
{{< /myshortcode >}}
```

## Best Practices

- Keep shortcodes simple and focused
- Document your custom shortcodes
- Use semantic HTML in shortcode templates
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
