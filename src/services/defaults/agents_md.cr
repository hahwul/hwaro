module Hwaro
  module Services
    module Defaults
      class AgentsMd
        def self.remote_content : String
          <<-CONTENT
            # AGENTS.md - AI Agent Instructions for Hwaro Site

            This document provides instructions for AI agents working on this Hwaro-generated website.

            ## Project Overview

            This is a static website built with [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator written in Crystal.

            ## Essential Commands

            | Command | Description |
            |---------|-------------|
            | `hwaro build` | Build the site to `public/` directory |
            | `hwaro serve` | Start development server with live reload |
            | `hwaro new <path>` | Create new content from archetype |
            | `hwaro deploy` | Deploy the site (requires configuration) |
            | `hwaro build --drafts` | Include draft content |
            | `hwaro serve -p 8080` | Serve on custom port (default: 3000) |
            | `hwaro build --base-url "https://example.com"` | Set base URL for production |

            ## Directory Structure

            ```
            .
            ├── config.toml          # Site configuration
            ├── content/             # Markdown content files
            │   ├── _index.md        # Homepage content
            │   └── blog/            # Blog section
            │       ├── _index.md    # Section listing page
            │       └── *.md         # Individual pages
            ├── templates/           # Jinja2 templates (Crinja)
            │   ├── base.html        # Base layout (optional)
            │   ├── page.html        # Page template
            │   ├── section.html     # Section listing template
            │   └── shortcodes/      # Shortcode templates
            ├── static/              # Static assets (copied as-is)
            └── archetypes/          # Content templates for `hwaro new`
            ```

            ## Notes for AI Agents

            1. **Front matter is TOML** (`+++`), not YAML (`---`).
            2. **Rendered content** is `{{ content | safe }}`, not `{{ page.content }}`.
            3. **Custom metadata** is `page.extra.field`, not `page.params.field`.
            4. **Always preview** with `hwaro serve` before committing.
            5. **Validate TOML syntax** in config.toml and front matter after edits.
            6. **Use `{{ base_url }}` prefix** for URLs in templates.
            7. **Escape user content** with `{{ value | escape }}` in templates.

            ## Full Reference

            For detailed documentation on content, templates, configuration, and more:

            - [Hwaro Documentation](https://hwaro.hahwul.com)
            - [Configuration Guide](https://hwaro.hahwul.com/start/config/)
            - [Full LLM Reference](https://hwaro.hahwul.com/llms-full.txt) — comprehensive reference optimized for AI agents

            To generate the full embedded AGENTS.md locally, run:
            ```
            hwaro tool agents-md --local --write
            ```

            ## Site-Specific Instructions

            <!-- Add your site-specific rules and conventions below -->
            CONTENT
        end

        def self.content : String
          <<-CONTENT
            # AGENTS.md - AI Agent Instructions for Hwaro Site

            This document provides instructions for AI agents working on this Hwaro-generated website.

            ## Project Overview

            This is a static website built with [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator written in Crystal.

            ## Essential Commands

            | Command | Description |
            |---------|-------------|
            | `hwaro build` | Build the site to `public/` directory |
            | `hwaro serve` | Start development server with live reload |
            | `hwaro new <path>` | Create new content from archetype |
            | `hwaro deploy` | Deploy the site (requires configuration) |
            | `hwaro build --drafts` | Include draft content |
            | `hwaro serve -p 8080` | Serve on custom port (default: 3000) |
            | `hwaro build --base-url "https://example.com"` | Set base URL for production |

            ## Directory Structure

            ```
            .
            ├── config.toml          # Site configuration
            ├── content/             # Markdown content files
            │   ├── _index.md        # Homepage content
            │   └── blog/            # Blog section
            │       ├── _index.md    # Section listing page
            │       └── *.md         # Individual pages
            ├── templates/           # Jinja2 templates (Crinja)
            │   ├── base.html        # Base layout (optional)
            │   ├── page.html        # Page template
            │   ├── section.html     # Section listing template
            │   ├── taxonomy.html    # Taxonomy listing
            │   ├── taxonomy_term.html # Taxonomy term page
            │   ├── 404.html         # Error page
            │   └── shortcodes/      # Shortcode templates
            ├── static/              # Static assets (copied as-is)
            └── archetypes/          # Content templates for `hwaro new`
            ```

            ## Content

            ### Pages

            Create `.md` files in `content/`. Front matter uses TOML (`+++`).

            ```toml
            +++
            title = "Page Title"
            date = "2024-01-15"
            description = "SEO description"
            draft = false
            tags = ["tag1", "tag2"]
            image = "/images/cover.png"
            weight = 0
            toc = true
            authors = ["Author"]
            template = "page"

            [extra]
            custom_field = "value"
            +++

            Markdown content here.
            ```

            | Field | Type | Description |
            |-------|------|-------------|
            | title | string | Page title (required) |
            | date | string | Publication date (YYYY-MM-DD) |
            | description | string | SEO description |
            | draft | bool | Exclude from production builds |
            | tags | array | Tag taxonomy terms |
            | image | string | Featured image for social sharing |
            | weight | int | Sort order (lower = first) |
            | toc | bool | Enable table of contents |
            | template | string | Custom template name |
            | slug | string | Custom URL slug |
            | aliases | array | Redirect URLs to this page |
            | authors | array | Author names |
            | extra | table | Custom metadata (access via `page.extra`) |

            ### Sections

            A directory with `_index.md` groups related content.

            ```toml
            +++
            title = "Blog"
            sort_by = "date"
            paginate = 10
            +++
            ```

            | Field | Type | Description |
            |-------|------|-------------|
            | sort_by | string | Sort by: `date`, `weight`, `title` |
            | paginate | int | Pages per page |
            | transparent | bool | Pass pages to parent section |
            | generate_feeds | bool | Generate RSS feed for this section |
            | page_template | string | Default template for child pages |

            ### Internal Links

            Use `@/` to link to content by source path:
            ```markdown
            [Read the post](@/blog/my-post.md)
            [Blog section](@/blog/_index.md)
            ```

            ### Content Summary

            Use `<!-- more -->` to define a summary for listings:
            ```markdown
            This appears in listings.

            <!-- more -->

            Full content continues here.
            ```

            ## Templates

            ### Template Selection

            | Content | Template |
            |---------|----------|
            | `content/index.md` | `index.html` or `page.html` |
            | `content/about.md` | `page.html` |
            | `content/blog/_index.md` | `section.html` |
            | `content/blog/post.md` | `page.html` |
            | Taxonomy listing | `taxonomy.html` |
            | Taxonomy term | `taxonomy_term.html` |

            ### Key Variables

            **In page.html:**
            ```jinja
            {{ page.title }}          {# Page title #}
            {{ page.date }}           {# Publication date #}
            {{ page.url }}            {# Relative URL #}
            {{ page.description }}    {# SEO description #}
            {{ page.image }}          {# Featured image #}
            {{ page.reading_time }}   {# Reading time in minutes #}
            {{ page.word_count }}     {# Word count #}
            {{ page.extra.field }}    {# Custom front matter #}
            {{ content | safe }}      {# Rendered HTML content #}
            {{ toc | safe }}          {# Table of contents HTML #}
            ```

            **In section.html:**
            ```jinja
            {{ section.title }}
            {{ section.pages }}       {# Array of pages #}
            {{ section.pages_count }}
            {{ section.subsections }} {# Child sections #}
            ```

            **Global:**
            ```jinja
            {{ site.title }}
            {{ site.description }}
            {{ base_url }}
            {{ current_year }}
            ```

            **SEO (pre-rendered HTML):**
            ```jinja
            {{ og_all_tags | safe }}       {# OpenGraph + Twitter meta tags #}
            {{ canonical_tag | safe }}     {# Canonical link #}
            {{ jsonld | safe }}            {# JSON-LD structured data #}
            {{ highlight_tags | safe }}    {# Syntax highlighting CSS + JS #}
            {{ auto_includes | safe }}     {# Auto-included CSS + JS #}
            ```

            ### Navigation

            ```jinja
            {# Previous/Next page #}
            {% if page.lower %}<a href="{{ page.lower.url }}">← {{ page.lower.title }}</a>{% endif %}
            {% if page.higher %}<a href="{{ page.higher.url }}">{{ page.higher.title }} →</a>{% endif %}

            {# Breadcrumbs #}
            {% for ancestor in page.ancestors %}
              <a href="{{ ancestor.url }}">{{ ancestor.title }}</a> /
            {% endfor %}
            ```

            ### Shortcodes

            Reusable components in `templates/shortcodes/`. Use in markdown:
            ```markdown
            {{ youtube(id="dQw4w9WgXcQ") }}
            {% alert(type="warning") %}Warning text{% endalert %}
            ```

            ### Common Filters

            | Filter | Description |
            |--------|-------------|
            | `safe` | Output raw HTML |
            | `escape` | Escape HTML entities |
            | `default(value="fallback")` | Default value if nil |
            | `truncate(length=100)` | Truncate string |
            | `slugify` | Convert to URL slug |
            | `strip_html` | Remove HTML tags |
            | `markdownify` | Render markdown to HTML |
            | `date(format="%Y-%m-%d")` | Format date |
            | `upper` / `lower` | Case conversion |
            | `join(sep=", ")` | Join array |

            ## Configuration

            Key `config.toml` sections:

            ```toml
            title = "My Site"
            base_url = "https://example.com"

            [highlight]
            enabled = true
            theme = "github-dark"

            [search]
            enabled = true

            [sitemap]
            enabled = true

            [feeds]
            enabled = true

            [og]
            default_image = "/images/og.png"
            twitter_card = "summary_large_image"

            [[taxonomies]]
            name = "tags"
            ```

            See [Hwaro Documentation](https://hwaro.hahwul.com/start/config/) for the full configuration reference.

            ## Notes for AI Agents

            1. **Front matter is TOML** (`+++`), not YAML (`---`).
            2. **Rendered content** is `{{ content | safe }}`, not `{{ page.content }}`.
            3. **Custom metadata** is `page.extra.field`, not `page.params.field`.
            4. **Always preview** with `hwaro serve` before committing.
            5. **Validate TOML syntax** in config.toml and front matter after edits.
            6. **Use `{{ base_url }}` prefix** for URLs in templates.
            7. **Escape user content** with `{{ value | escape }}` in templates.

            ## Site-Specific Instructions

            <!-- Add your site-specific rules and conventions below -->
            CONTENT
        end
      end
    end
  end
end
