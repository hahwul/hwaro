module Hwaro
  module Services
    module Defaults
      class AgentsMd
        def self.content : String
          <<-CONTENT
          # AGENTS.md - AI Agent Instructions for Hwaro Site

          This document provides instructions for AI agents working on this Hwaro-generated website.

          ## Project Overview

          This is a static website built with [Hwaro](https://github.com/geomagilles/hwaro), a fast and lightweight static site generator written in Crystal.

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
          ├── templates/           # ECR templates
          │   ├── header.ecr       # Site header partial
          │   ├── footer.ecr       # Site footer partial
          │   ├── page.ecr         # Default page template
          │   ├── section.ecr      # Section listing template
          │   └── 404.ecr          # Not found page
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
          | template    | string   | Custom template name (without .ecr)      |
          | weight      | integer  | Sort order (lower = first)               |
          | slug        | string   | Custom URL slug                          |
          | aliases     | array    | URL redirects to this page               |

          ### Creating Sections

          1. Create a directory under `content/` (e.g., `content/projects/`)
          2. Add `_index.md` for the section listing page
          3. Add individual `.md` files for section items

          ## Template Development

          ### Template Location

          All templates are in the `templates/` directory using ECR (Embedded Crystal) syntax.

          ### Available Template Variables

          #### Site Variables
          - `<%= site_title %>` - Site title from config
          - `<%= site_description %>` - Site description from config
          - `<%= base_url %>` - Base URL of the site

          #### Page Variables
          - `<%= page_title %>` - Current page title
          - `<%= content %>` - Rendered page content
          - `<%= page_section %>` - Current section name
          - `<%= page_description %>` - Page description (falls back to site description)
          - `<%= page_image %>` - Page image URL

          #### Section Variables (in section.ecr)
          - `<%= section_list %>` - HTML list of pages in section

          #### Navigation & SEO
          - `<%= og_tags %>` - OpenGraph meta tags
          - `<%= twitter_tags %>` - Twitter Card meta tags
          - `<%= og_all_tags %>` - Both OG and Twitter tags
          - `<%= auto_includes_css %>` - Auto-included CSS files
          - `<%= auto_includes_js %>` - Auto-included JS files
          - `<%= auto_includes %>` - Both CSS and JS includes

          ### Including Partials

          ```erb
          <%= render "header" %>
          <%= render "footer" %>
          ```

          ### Template Best Practices

          1. **Header/Footer Pattern**: Use partials for consistent site structure
          2. **Semantic HTML**: Use proper HTML5 semantic elements
          3. **Responsive Design**: Include viewport meta tag and responsive CSS
          4. **Accessibility**: Include proper ARIA labels and alt text

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

          1. Edit `templates/header.ecr` for site header and navigation
          2. Edit `templates/footer.ecr` for site footer
          3. Modify `<style>` section in header.ecr or create CSS files
          4. Edit `templates/page.ecr` for page layout

          ### Adding Navigation Links

          Edit the `<nav>` section in `templates/header.ecr`:

          ```html
          <nav>
            <a href="<%= base_url %>/">Home</a>
            <a href="<%= base_url %>/about/">About</a>
            <a href="<%= base_url %>/blog/">Blog</a>
            <!-- Add more links here -->
          </nav>
          ```

          ### Enabling Features

          Edit `config.toml` to enable/disable features:

          - **Search**: Set `[search] enabled = true`
          - **RSS Feed**: Set `[feeds] enabled = true`
          - **Sitemap**: Set `[sitemap] enabled = true`
          - **Taxonomies**: Add `[[taxonomies]]` sections

          ## Notes for AI Agents

          1. **Always preserve front matter** when editing content files
          2. **Test changes** with `hwaro serve` before finalizing
          3. **Use consistent formatting** in Markdown files
          4. **Check template syntax** - ECR uses `<%= %>` for output
          5. **Validate TOML syntax** in config.toml after edits
          6. **Keep URLs relative** using `<%= base_url %>` prefix
          CONTENT
        end
      end
    end
  end
end
