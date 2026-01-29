module Hwaro
  module Services
    module Defaults
      class AgentsMd
        def self.content : String
          <<-CONTENT
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          This document provides instructions for AI agents working on this Hwaro-generated website.

          ## Project Overview

          This is a static website built with [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator written in Crystal.

          ## Directory Structure

          ```
          .
          ├── config.toml          # Site configuration
          ├── content/             # Markdown content files
          │   ├── _index.md        # Homepage content
          │   ├── about.md         # About page
          │   └── blog/            # Blog section
          │       ├── _index.md    # Blog listing page
          │       └── *.md         # Individual blog posts
          ├── templates/           # Jinja2 templates (.html, .j2)
          │   ├── header.html      # Site header partial
          │   ├── footer.html      # Site footer partial
          │   ├── page.html        # Default page template
          │   ├── section.html     # Section listing template
          │   └── 404.html         # Not found page
          └── static/              # Static assets (copied as-is)
          ```

          ## Content Management

          ### Creating New Pages

          Create a new `.md` file in the `content/` directory:

          ```markdown
          +++
          title = "Page Title"
          date = "2024-01-01"
          draft = false
          +++

          Your markdown content here.
          ```

          ### Front Matter Fields

          | Field       | Type     | Description                              |
          |-------------|----------|------------------------------------------|
          | title       | string   | Page title (required)                    |
          | date        | string   | Publication date (YYYY-MM-DD)            |
          | draft       | boolean  | If true, excluded from production build  |
          | description | string   | Page description for SEO                 |
          | image       | string   | Featured image URL for social sharing    |
          | tags        | array    | List of tags                             |
          | categories  | array    | List of categories                       |
          | template    | string   | Custom template name (without extension) |
          | weight      | integer  | Sort order (lower = first)               |
          | slug        | string   | Custom URL slug                          |
          | aliases     | array    | URL redirects to this page               |

          ### Creating Sections

          1. Create a directory under `content/` (e.g., `content/projects/`)
          2. Add `_index.md` for the section listing page
          3. Add individual `.md` files for section items

          ## Template Development

          ### Template Location

          All templates are in the `templates/` directory using Jinja2 syntax (powered by Crinja).
          Supported extensions: `.html`, `.j2`, `.jinja2`, `.jinja`

          ### Jinja2 Syntax Basics

          - `{{ variable }}` - Print a variable
          - `{% if condition %}...{% endif %}` - Conditionals
          - `{% for item in items %}...{% endfor %}` - Loops
          - `{% include "partial.html" %}` - Include another template
          - `{% extends "base.html" %}` - Template inheritance
          - `{{ value | filter }}` - Apply a filter
          - `{# comment #}` - Comments (not rendered)

          ### Available Template Variables

          #### Site Variables
          - `{{ site_title }}` - Site title from config
          - `{{ site_description }}` - Site description from config
          - `{{ base_url }}` - Base URL of the site
          - `{{ site.title }}`, `{{ site.description }}`, `{{ site.base_url }}` - Site object

          #### Page Variables
          Variables can be accessed both as flat variables and via the page object:
          - `{{ page_title }}` / `{{ page.title }}` - Current page title
          - `{{ page_description }}` / `{{ page.description }}` - Page description (falls back to site description)
          - `{{ page_url }}` / `{{ page.url }}` - Page URL
          - `{{ page_section }}` / `{{ page.section }}` - Current section name
          - `{{ page_date }}` / `{{ page.date }}` - Page date
          - `{{ page_image }}` / `{{ page.image }}` - Page image URL
          - `{{ content }}` - Rendered page content

          #### Page Object Properties
          - `{{ page.draft }}` - Is draft (boolean)
          - `{{ page.toc }}` - Show table of contents (boolean)

          #### Section Variables (in section.html)
          Variables can be accessed both as flat variables and via the section object:
          - `{{ section_title }}` / `{{ section.title }}` - Section title
          - `{{ section_description }}` / `{{ section.description }}` - Section description
          - `{{ section_list }}` / `{{ section.list }}` - HTML list of pages in section
          - `{{ section.pages }}` - Array of page objects for iteration
          - `{{ pagination }}` - Pagination navigation HTML (empty if disabled or single page)
          - `{{ toc }}` / `{{ toc_obj.html }}` - Table of contents HTML

          #### Taxonomy Variables
          - `{{ taxonomy_name }}` - Name of taxonomy (e.g., "tags")
          - `{{ taxonomy_term }}` - Current taxonomy term

          #### Navigation & SEO
          - `{{ og_tags }}` - OpenGraph meta tags
          - `{{ twitter_tags }}` - Twitter Card meta tags
          - `{{ og_all_tags }}` - Both OG and Twitter tags
          - `{{ auto_includes_css }}` - Auto-included CSS files
          - `{{ auto_includes_js }}` - Auto-included JS files
          - `{{ auto_includes }}` - Both CSS and JS includes
          - `{{ highlight_css }}` - Syntax highlighting CSS
          - `{{ highlight_js }}` - Syntax highlighting JS

          ### Including Partials

          ```jinja
          {% include "header.html" %}
          {% include "footer.html" %}
          ```

          ### Pagination

          Enable global pagination in `config.toml`:

          ```toml
          [pagination]
          enabled = true
          per_page = 10
          ```

          Override per section in a section `_index.md` front matter:

          ```toml
          +++
          paginate = 10
          pagination_enabled = true
          sort_by = "date"   # "date" | "title" | "weight"
          reverse = false
          +++
          ```

          ### Conditional Rendering

          ```jinja
          {% if page.draft %}
            <span class="draft-badge">Draft</span>
          {% endif %}

          {% if page.section == "blog" %}
            <article class="blog-post">{{ content }}</article>
          {% else %}
            <main>{{ content }}</main>
          {% endif %}

          {% if page.description %}
            <meta name="description" content="{{ page.description }}">
          {% endif %}
          ```

          ### Loops

          ```jinja
          {% for tag in tags %}
            <span class="tag">{{ tag }}</span>
          {% endfor %}
          ```

          ### Filters

          Built-in filters:
          - `{{ text | upper }}` - Uppercase
          - `{{ text | lower }}` - Lowercase
          - `{{ text | title }}` - Title case
          - `{{ text | trim }}` - Remove whitespace
          - `{{ text | escape }}` - HTML escape
          - `{{ list | join(", ") }}` - Join array
          - `{{ list | first }}` - First item
          - `{{ list | last }}` - Last item
          - `{{ list | length }}` - Array length
          - `{{ text | default("fallback") }}` - Default value

          Custom Hwaro filters:
          - `{{ date | date("%Y-%m-%d") }}` - Format date
          - `{{ text | truncate_words(50) }}` - Truncate by words
          - `{{ text | slugify }}` - Convert to URL slug
          - `{{ url | absolute_url }}` - Make URL absolute
          - `{{ url | relative_url }}` - Prefix with base_url
          - `{{ html | strip_html }}` - Remove HTML tags
          - `{{ markdown | markdownify }}` - Render markdown
          - `{{ text | xml_escape }}` - XML escape
          - `{{ data | jsonify }}` - JSON encode

          ### Template Inheritance

          Base template (`templates/base.html`):
          ```jinja
          <!DOCTYPE html>
          <html>
          <head>
            <title>{% block title %}{{ site_title }}{% endblock %}</title>
          </head>
          <body>
            {% block content %}{% endblock %}
          </body>
          </html>
          ```

          Child template (`templates/page.html`):
          ```jinja
          {% extends "base.html" %}

          {% block title %}{{ page.title }} - {{ site.title }}{% endblock %}

          {% block content %}
            <main>{{ content }}</main>
          {% endblock %}
          ```

          ### Template Best Practices

          1. **Use Template Inheritance**: Create a base layout for consistency
          2. **Semantic HTML**: Use proper HTML5 semantic elements
          3. **Responsive Design**: Include viewport meta tag and responsive CSS
          4. **Accessibility**: Include proper ARIA labels and alt text
          5. **Keep Templates Clean**: Move complex logic to macros

          ## Styling Guidelines

          ### CSS Location

          - Place CSS files in `static/assets/css/` or `static/css/`
          - Use numeric prefixes for load order: `01-reset.css`, `02-main.css`
          - Enable auto-includes in `config.toml` for automatic loading

          ### Recommended CSS Structure

          ```css
          /* Reset/Normalize */
          /* Typography */
          /* Layout */
          /* Components */
          /* Utilities */
          ```

          ## Building & Previewing

          ```bash
          # Build the site
          hwaro build

          # Build with drafts included
          hwaro build --drafts

          # Start development server with live reload
          hwaro serve

          # Start server and open browser
          hwaro serve --open
          ```

          ## Common Tasks

          ### Adding a Blog Post

          1. Create `content/blog/my-new-post.md`
          2. Add front matter with title and date
          3. Write content in Markdown
          4. Run `hwaro serve` to preview

          ### Customizing the Design

          1. Edit `templates/header.html` for site header and navigation
          2. Edit `templates/footer.html` for site footer
          3. Modify `<style>` section in header.html or create CSS files
          4. Edit `templates/page.html` for page layout

          ### Adding Navigation Links

          Edit the `<nav>` section in `templates/header.html`:

          ```html
          <nav>
            <a href="{{ base_url }}/">Home</a>
            <a href="{{ base_url }}/about/">About</a>
            <a href="{{ base_url }}/blog/">Blog</a>
            <!-- Add more links here -->
          </nav>
          ```

          ### Active Navigation Links

          ```jinja
          <nav>
            <a href="{{ base_url }}/"{% if page.url == "/" %} class="active"{% endif %}>Home</a>
            <a href="{{ base_url }}/blog/"{% if page.section == "blog" %} class="active"{% endif %}>Blog</a>
          </nav>
          ```

          ### Enabling Features

          Edit `config.toml` to enable/disable features:

          - **Search**: Set `[search] enabled = true`
          - **RSS Feed**: Set `[feeds] enabled = true`
          - **Sitemap**: Set `[sitemap] enabled = true`
          - **Taxonomies**: Add `[[taxonomies]]` sections
          - **Safe Markdown**: Set `[markdown] safe = true` to strip raw HTML

          ### Markdown Configuration

          Control how markdown is parsed in `config.toml`:

          ```toml
          [markdown]
          safe = true   # Strip raw HTML from markdown (default: false)
          ```

          When `safe = true`, raw HTML in markdown files is replaced with `<!-- raw HTML omitted -->` comments. This is useful for user-generated content or when you want to ensure only markdown syntax is used.

          ## Shortcodes

          Shortcodes provide reusable template snippets. Place them in `templates/shortcodes/`.

          ### Using Shortcodes in Content

          ```markdown
          {{ shortcode("alert", type="warning", message="Be careful!") }}
          ```

          ### Creating Shortcodes

          Create `templates/shortcodes/alert.html`:
          ```jinja
          <div class="alert alert-{{ type | default('info') }}">
            <strong>{{ type | upper }}:</strong> {{ message }}
          </div>
          ```

          ## Notes for AI Agents

          1. **Always preserve front matter** when editing content files
          2. **Test changes** with `hwaro serve` before finalizing
          3. **Use consistent formatting** in Markdown files
          4. **Check template syntax** - Jinja2 uses `{{ }}` for output, `{% %}` for logic
          5. **Validate TOML syntax** in config.toml after edits
          6. **Keep URLs relative** using `{{ base_url }}` prefix
          7. **Use filters** for data transformation instead of complex logic
          8. **Escape user content** with `{{ value | escape }}` when needed
          CONTENT
        end
      end
    end
  end
end
