# Hwaro - Agent Instructions

## Project Overview

Hwaro is a fast and lightweight static site generator written in Crystal. It provides a flexible, extensible architecture for building static websites with support for markdown content, templates, SEO features, multilingual support, deployment, and lifecycle hooks.

## Core Architecture

### Directory Structure

```
src/
├── cli/              # Command-line interface and command registry
│   └── commands/     # Individual CLI commands (init, build, serve, new, deploy, tool)
│       └── tool/     # Tool subcommands (convert, list, check)
├── config/           # Configuration loading and options
│   └── options/      # Command option structs (build, serve, init, new, deploy)
├── content/          # Content processing domain
│   ├── hooks/        # Lifecycle hook implementations (markdown, seo, taxonomy)
│   ├── pagination/   # Content pagination logic (paginator, renderer)
│   ├── processors/   # Content processors (markdown, html, json, xml, template, etc.)
│   └── seo/          # SEO generators (sitemap, feeds, robots, llms, tags)
├── core/             # Core build orchestration
│   ├── build/        # Builder, cache, and parallel processing
│   └── lifecycle/    # Lifecycle management system (manager, hooks, phases, context)
├── models/           # Data structures (config, page, site, section, toc, deployment)
├── services/         # Non-build features
│   ├── defaults/     # Default file generators (agents_md, config, content, templates)
│   ├── scaffolds/    # Project scaffolding (base, simple, blog, docs, registry)
│   └── server/       # Development server
└── utils/            # Utility modules (logger, command_runner, profiler, debug_printer, sort_utils, text_utils)
```

### Key Architectural Patterns

1. **Lifecycle Hook System**: The project uses a sophisticated lifecycle system that allows extensibility through hooks at various build phases. The build process is divided into 8 phases:
   - **Initialize**: Setup cache, output directory, load config
   - **ReadContent**: Collect content files from filesystem
   - **ParseContent**: Parse front matter and extract metadata
   - **Transform**: Content transformation (e.g., Markdown → HTML)
   - **Render**: Apply templates to transformed content
   - **Generate**: Generate SEO files, search index, taxonomies, etc.
   - **Write**: Write rendered pages to filesystem
   - **Finalize**: Cleanup, save cache, final operations
   
   Each phase has before/after hook points for extensibility. Modules can implement the `Hookable` interface or use the `HookDSL` for registering hooks with priorities. See `src/core/lifecycle/` for implementation.

2. **Processor Registry Pattern**: Content processors follow a registry pattern allowing dynamic registration and discovery. See `src/content/processors/base.cr`.

3. **Command Registry Pattern**: CLI commands use a registry system for dynamic command management, supporting potential plugin-based command extensions.

4. **Builder Pattern**: The main builder (`src/core/build/builder.cr`) orchestrates content collection, template rendering, and parallel processing with caching.

5. **Scaffold Registry Pattern**: Project scaffolds use a registry pattern for managing available scaffold types (simple, blog, docs). See `src/services/scaffolds/registry.cr`.

6. **Build Context Pattern**: A `BuildContext` object (`src/core/lifecycle/context.cr`) carries shared state across the entire build lifecycle, including pages, sections, raw files, templates, metadata, and build statistics.

## Code Style & Conventions

### Crystal-Specific

- **Indentation**: Use 2 spaces (as defined in `.editorconfig`)
- **End of Line**: LF (Unix-style)
- **Charset**: UTF-8
- **Final Newline**: Always include
- **Trailing Whitespace**: Remove

### Naming Conventions

- **Modules/Classes**: PascalCase (e.g., `MarkdownProcessor`, `BuildOptions`)
- **Methods/Variables**: snake_case (e.g., `process_content`, `base_url`)
- **Constants**: SCREAMING_SNAKE_CASE
- **File names**: snake_case matching the main class/module (e.g., `markdown_processor.cr`)

### Module Organization

- Each module should have a clear comment at the top explaining its purpose
- Group related functionality in namespaces (e.g., `Hwaro::Content::Processors`)
- Use `require` statements at the top in logical grouping order:
  1. Standard library
  2. External dependencies
  3. Internal utilities
  4. Internal models
  5. Internal modules

### Code Documentation

- Add comments for public APIs and complex logic
- Use descriptive variable and method names to reduce need for inline comments
- Document abstract classes and interfaces thoroughly
- Include usage examples in comments for plugin/extension points

## Development Guidelines

### Building & Testing

```bash
# Install dependencies
shards install

# Build the project
shards build

# Run tests
crystal spec
```

### Adding New Features

#### 1. Content Processors

To add a new content processor:

1. Create a new file in `src/content/processors/`
2. Inherit from `Hwaro::Content::Processors::Base`
3. Implement required methods: `name`, `extensions`, `process`
4. Register the processor in the Registry
5. Add the require statement in `src/hwaro.cr`

Example structure:
```crystal
class MyProcessor < Hwaro::Content::Processors::Base
  def name : String
    "my-processor"
  end

  def extensions : Array(String)
    [".myext"]
  end

  def process(content : String, context : ProcessorContext) : ProcessorResult
    # Process content - example: convert to uppercase
    transformed = content.upcase
    ProcessorResult.new(content: transformed)
  end
end

# Register the processor
Hwaro::Content::Processors::Registry.register(MyProcessor.new)
```

#### 2. CLI Commands

To add a new CLI command:

1. Create a new file in `src/cli/commands/`
2. Define command metadata constants and `FLAGS` array (single source of truth)
3. Implement `self.metadata` class method returning `CommandInfo`
4. Implement `run(args)` method with OptionParser
5. Register in `CommandRegistry` using metadata in `src/cli/runner.cr`
6. Add the require statement

Example command structure:
```crystal
require "../metadata"

class MyCommand
  # Single source of truth for command metadata
  NAME        = "mycommand"
  DESCRIPTION = "My command description"
  POSITIONAL_ARGS    = ["arg1"]  # Optional positional arguments
  POSITIONAL_CHOICES = [] of String  # Valid choices for positional args

  # Flags defined here are used for BOTH OptionParser AND completion generation
  FLAGS = [
    FlagInfo.new(short: "-f", long: "--flag", description: "A boolean flag"),
    FlagInfo.new(short: "-o", long: "--option", description: "Option with value", takes_value: true, value_hint: "VALUE"),
    HELP_FLAG,
  ]

  def self.metadata : CommandInfo
    CommandInfo.new(
      name: NAME,
      description: DESCRIPTION,
      flags: FLAGS,
      positional_args: POSITIONAL_ARGS,
      positional_choices: POSITIONAL_CHOICES
    )
  end

  def run(args : Array(String))
    # Use OptionParser as usual
  end
end
```

When you modify `FLAGS` in any command file, the shell completion scripts automatically reflect the changes.

##### Tool Subcommands

To add a new tool subcommand:

1. Create a new file in `src/cli/commands/tool/`
2. Follow the same metadata pattern as regular commands
3. Register in `ToolCommand.subcommands` and `run` method in `src/cli/commands/tool_command.cr`

Existing tool subcommands:
- `convert` - Convert frontmatter between YAML and TOML formats
- `list` - List content files by status (all, drafts, published)
- `check` - Check for dead links in content files

#### 3. Lifecycle Hooks

To add new hooks:

1. Create a module that includes `Hwaro::Core::Lifecycle::Hookable`
2. Implement `register_hooks(manager : Manager)` method
3. Register hooks using `manager.before`, `manager.after`, or `manager.on`
4. Add to the hooks collection in `src/content/hooks.cr`

#### 4. SEO Features

SEO-related features live in `src/content/seo/`:
- `feeds.cr` - RSS/Atom feed generation
- `sitemap.cr` - Sitemap XML generation
- `robots.cr` - Robots.txt generation
- `llms.cr` - LLM instructions file generator for AI/LLM crawler instructions
- `tags.cr` - Canonical URL and hreflang tag generation for multilingual sites

#### 5. Search Feature

Search functionality is implemented in `src/content/search.cr`:
- Supports Fuse.js compatible JSON format
- Configurable search fields (title, content, tags, url, section, description)
- Automatic search index generation during build

#### 6. Taxonomies

Taxonomy system for categorizing content (tags, categories, etc.) in `src/content/taxonomies.cr`:
- Automatic taxonomy index and term page generation
- Support for custom taxonomies defined in config
- Feed generation for taxonomy terms
- Pagination support for large taxonomy listings

#### 7. Pagination

Content pagination logic in `src/content/pagination/`:
- `paginator.cr` - Core pagination logic
- `renderer.cr` - HTML rendering for pagination controls
- Supports section pagination and taxonomy pagination
- Custom pagination path via `paginate_path` front matter field

#### 8. Archetypes

Archetypes are content templates used by `hwaro new` to create new content files with predefined front matter and content structure.

Directory structure:
```
archetypes/
├── default.md          # Default template for all content
├── posts.md            # Template for content/posts/
├── docs.md             # Template for content/docs/
└── tools/
    └── develop.md      # Template for content/tools/develop/
```

Implementation details:
- `src/services/creator.cr` - Creator service with archetype matching logic
- `src/config/options/new_options.cr` - NewOptions with `archetype` property
- `src/cli/commands/new_command.cr` - `-a, --archetype` flag

Available placeholders in archetype files:
- `{{ title }}` or `{{title}}` - Content title
- `{{ date }}` or `{{date}}` - Current date/time
- `{{ draft }}` or `{{draft}}` - Draft status (true/false)

Archetype matching priority:
1. Explicit `-a` flag: `hwaro new -t "Title" -a posts` uses `archetypes/posts.md`
2. Path-based matching: `hwaro new posts/hello.md` checks `archetypes/posts.md`
3. Nested path fallback: `hwaro new tools/develop/x.md` tries `archetypes/tools/develop.md`, then `archetypes/tools.md`
4. Default archetype: `archetypes/default.md`
5. Built-in template if no archetype found

Example archetype (`archetypes/posts.md`):
```markdown
---
title: "{{ title }}"
date: {{ date }}
draft: false
author: ""
tags: []
---

# {{ title }}

Write your content here.
```

Usage examples:
```bash
# Path-based archetype matching
hwaro new posts/my-article.md

# Explicit archetype with title
hwaro new -t "My Article" -a posts

# Creates in drafts/ with posts archetype
hwaro new -t "Draft Post" -a posts
```

#### 9. User-defined Build Hooks

User-defined build hooks allow running custom shell commands before and after the build process. This is useful for tasks like:
- Installing dependencies before build
- Running custom scripts (preprocessing, data fetching)
- Post-processing assets (minification, optimization)
- Deployment automation

Configuration in `config.toml`:
```toml
[build]
hooks.pre = ["npm install", "python scripts/preprocess.py"]   # Commands to run before build
hooks.post = ["npm run minify", "rsync -av public/ server:/var/www/"]  # Commands to run after build
```

Implementation details:
- `src/utils/command_runner.cr` - Shell command execution utility
- `src/models/config.cr` - `BuildConfig` and `BuildHooksConfig` classes
- Commands are executed sequentially in the order defined
- Pre-hooks failure aborts the build process
- Post-hooks failure shows a warning but doesn't fail the build
- Hooks are executed for both `hwaro build` and `hwaro serve` commands
- During serve mode, hooks are re-executed on each rebuild (config changes are picked up)

Example use cases:
```toml
# Install npm dependencies and compile TypeScript before build
[build]
hooks.pre = ["npm ci", "npx tsc"]

# Optimize images and deploy after build
[build]
hooks.post = [
  "npx imagemin public/images/* --out-dir=public/images",
  "./scripts/deploy.sh"
]
```

#### 10. Auto Includes

Auto includes automatically load CSS and JS files from specified static directories into all pages. This eliminates the need to manually add each asset file to templates.

Configuration in `config.toml`:
```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]  # Directories under static/ to scan
```

Implementation details:
- `src/models/config.cr` - `AutoIncludesConfig` class with `css_tags()`, `js_tags()`, `all_tags()` methods
- Files are scanned from `static/{dir}/**/*.css` and `static/{dir}/**/*.js`
- Files are included alphabetically - use numeric prefixes for ordering (e.g., `01-reset.css`, `02-main.css`)
- CSS files generate `<link rel="stylesheet">` tags
- JS files generate `<script src="">` tags

Template variables:
- `{{ auto_includes_css }}` - CSS link tags only (place in `<head>`)
- `{{ auto_includes_js }}` - JS script tags only (place before `</body>`)
- `{{ auto_includes }}` - Both CSS and JS tags combined

Example directory structure:
```
static/
├── assets/
│   ├── css/
│   │   ├── 01-reset.css
│   │   ├── 02-typography.css
│   │   └── 03-layout.css
│   └── js/
│       ├── 01-utils.js
│       └── 02-app.js
```

Generated output:
```html
<!-- In <head> -->
<link rel="stylesheet" href="/assets/css/01-reset.css">
<link rel="stylesheet" href="/assets/css/02-typography.css">
<link rel="stylesheet" href="/assets/css/03-layout.css">

<!-- Before </body> -->
<script src="/assets/js/01-utils.js"></script>
<script src="/assets/js/02-app.js"></script>
```

#### 11. OpenGraph & Twitter Cards

Automatic generation of OpenGraph and Twitter Card meta tags for social sharing.

Configuration in `config.toml`:
```toml
[og]
default_image = "/images/og-default.png"   # Default image when page has no image
type = "article"                           # OpenGraph type (website, article, etc.)
twitter_card = "summary_large_image"       # Twitter card type
twitter_site = "@yourusername"             # Twitter @username for the site
twitter_creator = "@authorusername"        # Twitter @username for content creator
fb_app_id = "your_fb_app_id"               # Facebook App ID (optional)
```

Page-level front matter (overrides defaults):
```toml
+++
title = "My Article"
description = "Article description for social sharing"
image = "/images/article-cover.png"
+++
```

Implementation details:
- `src/models/config.cr` - `OpenGraphConfig` class with `og_tags()`, `twitter_tags()`, `all_tags()` methods
- `src/models/page.cr` - `description` and `image` properties
- `src/content/processors/markdown.cr` - Parses `description` and `image` from front matter
- `src/content/hooks/markdown_hooks.cr` - Assigns parsed values to page

Template variables:
- `{{ og_tags }}` - OpenGraph meta tags only
- `{{ twitter_tags }}` - Twitter Card meta tags only
- `{{ og_all_tags }}` - Both OG and Twitter tags combined
- `{{ page_description }}` - Page description (falls back to site description)
- `{{ page_image }}` - Page image (falls back to og.default_image)

Generated output example:
```html
<meta property="og:title" content="My Article">
<meta property="og:type" content="article">
<meta property="og:url" content="https://example.com/my-article/">
<meta property="og:description" content="Article description for social sharing">
<meta property="og:image" content="https://example.com/images/article-cover.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="My Article">
<meta name="twitter:description" content="Article description for social sharing">
<meta name="twitter:image" content="https://example.com/images/article-cover.png">
<meta name="twitter:site" content="@yourusername">
```

#### 12. Jinja2 Template Engine (Crinja)

Hwaro uses the Crinja library for Jinja2-compatible templating. Templates support the full Jinja2 syntax.

**Template File Extensions:**
- `.html` (recommended)
- `.j2`, `.jinja2`, `.jinja`

**Basic Syntax:**
- `{{ variable }}` - Print a variable
- `{% if condition %}...{% endif %}` - Conditionals
- `{% for item in items %}...{% endfor %}` - Loops
- `{% include "partial.html" %}` - Include another template
- `{% extends "base.html" %}` - Template inheritance
- `{{ value | filter }}` - Apply a filter
- `{# comment #}` - Comments (not rendered)

**Available Variables:**

Page variables:
- `{{ page_url }}` - Page URL (e.g., "/about/")
- `{{ page_section }}` - Page section (e.g., "blog")
- `{{ page_title }}` - Page title
- `{{ page_description }}` - Page description
- `{{ page_date }}` - Page date
- `{{ page_image }}` - Page image

Page object (with boolean properties):
- `{{ page.title }}`, `{{ page.url }}`, `{{ page.section }}`
- `{{ page.draft }}` - Is draft (boolean)
- `{{ page.toc }}` - Show TOC (boolean)
- `{{ page.is_index }}`, `{{ page.render }}`, `{{ page.generated }}`, `{{ page.in_sitemap }}`
- `{{ page.word_count }}` - Word count of the content
- `{{ page.reading_time }}` - Estimated reading time in minutes
- `{{ page.permalink }}` - Absolute URL with base_url
- `{{ page.summary }}` - Content summary (before `<!-- more -->` marker)
- `{{ page.authors }}` - List of author names
- `{{ page.language }}` - Language code (for multilingual sites)
- `{{ page.translations }}` - List of translation links

Site variables:
- `{{ site_title }}`, `{{ site_description }}`, `{{ base_url }}`
- `{{ site.title }}`, `{{ site.description }}`, `{{ site.base_url }}`

Content variables:
- `{{ content }}` - Rendered page content
- `{{ section_list }}` - HTML list of pages in section
- `{{ toc }}` - Table of contents HTML
- `{{ taxonomy_name }}`, `{{ taxonomy_term }}`

SEO/Meta variables:
- `{{ og_tags }}`, `{{ twitter_tags }}`, `{{ og_all_tags }}`
- `{{ highlight_css }}`, `{{ highlight_js }}`, `{{ highlight_tags }}`
- `{{ auto_includes_css }}`, `{{ auto_includes_js }}`, `{{ auto_includes }}`

Time-related variables:
- `{{ current_year }}` - Current year (e.g., 2025)
- `{{ current_date }}` - Current date in YYYY-MM-DD format
- `{{ current_datetime }}` - Current datetime in YYYY-MM-DD HH:MM:SS format
- `{{ now() }}` - Function that returns current datetime (supports format parameter)

**Example usage in templates:**
```jinja
<nav>
  <a href="{{ base_url }}/"{% if page_url == "/" %} class="active"{% endif %}>Home</a>
  <a href="{{ base_url }}/blog/"{% if page_section == "blog" %} class="active"{% endif %}>Blog</a>
  <a href="{{ base_url }}/about/"{% if page_url == "/about/" %} class="active"{% endif %}>About</a>
</nav>

{% if page_section == "blog" %}
  <article class="blog-post">
    {% if page.toc %}
    <div class="toc">{{ toc }}</div>
    {% endif %}
    {{ content }}
  </article>
{% elif page_section == "docs" %}
  <div class="documentation">
    {{ content }}
  </div>
{% else %}
  <main>
    {{ content }}
  </main>
{% endif %}

{% if page_description %}
<meta name="description" content="{{ page_description }}">
{% endif %}

{% if not page.draft %}
<p>Published</p>
{% endif %}

{% if page_section == "blog" and not page.draft %}
<p>Published blog post</p>
{% endif %}

{% if page_section == "blog" or page_section == "news" %}
<p>Content section</p>
{% endif %}
```

**Template Inheritance Example:**

Base template (`templates/base.html`):
```jinja
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ site_title }}{% endblock %}</title>
  {{ highlight_css }}
</head>
<body>
  {% block content %}{% endblock %}
  {{ highlight_js }}
</body>
</html>
```

Child template (`templates/page.html`):
```jinja
{% extends "base.html" %}

{% block title %}{{ page_title }} - {{ site_title }}{% endblock %}

{% block content %}
<main>{{ content }}</main>
{% endblock %}
```

**Custom Filters:**
- `{{ text | slugify }}` - Convert to URL slug
- `{{ text | truncate_words(50) }}` - Truncate by word count
- `{{ url | absolute_url }}` - Make URL absolute with base_url
- `{{ url | relative_url }}` - Prefix with base_url
- `{{ html | strip_html }}` - Remove HTML tags
- `{{ text | markdownify }}` - Render markdown
- `{{ text | xml_escape }}` - XML escape
- `{{ data | jsonify }}` - JSON encode
- `{{ date | date("%Y-%m-%d") }}` - Format date
- `{{ text | split(pat=",") }}` - Split string by separator
- `{{ html | safe }}` - Mark content as safe (no escaping)
- `{{ text | trim }}` - Remove leading/trailing whitespace
- `{{ value | default(value="fallback") }}` - Provide default value if empty

**Custom Tests:**
- `{% if page_url is startswith("/blog/") %}` - String starts with
- `{% if page_title is endswith("!") %}` - String ends with
- `{% if page_url is containing("products") %}` - String contains
- `{% if page_description is empty %}` - Value is empty
- `{% if page_title is present %}` - Value is not empty

**Shortcodes:**

Shortcodes allow reusable template components in content files. Two syntax patterns are supported:

1. **Direct call** (recommended):
```jinja
{{ shortcode_name(arg1="value1", arg2="value2") }}
```

2. **Explicit call**:
```jinja
{{ shortcode("shortcode_name", arg1="value1", arg2="value2") }}
```

Shortcode templates are stored in `templates/shortcodes/` directory.

Example shortcode template (`templates/shortcodes/alert.html`):
```jinja
{% if type and message %}
<div class="alert alert-{{ type }}">
  {{ message | safe }}
</div>
{% endif %}
```

Usage in content:
```markdown
{{ alert(type="warning", message="<strong>Be careful!</strong> This is important.") }}
```

Shortcode arguments support:
- Double quotes: `arg="value"`
- Single quotes: `arg='value'`
- Unquoted values: `arg=value`

**Implementation details:**
- `src/content/processors/template.cr` - `TemplateEngine` class wrapping Crinja
- `src/core/build/builder.cr` - Template rendering in `apply_template()` method, shortcode processing in `process_shortcodes_jinja()`
- Templates are loaded from `templates/` directory with FileSystemLoader

#### 13. Deployment

Hwaro includes a built-in deployment system for publishing built sites to various targets.

**CLI Usage:**
```bash
# Deploy to default target
hwaro deploy

# Deploy to specific target(s)
hwaro deploy prod staging

# Deploy with options
hwaro deploy --dry-run --confirm
hwaro deploy --force --max-deletes -1

# List configured targets
hwaro deploy --list-targets
```

**Configuration in `config.toml`:**
```toml
[deployment]
confirm = false           # Ask for confirmation before deploying
dry_run = false            # Show changes without writing
force = false              # Force upload (ignore file comparisons)
max_deletes = 256          # Maximum number of deletes (-1 to disable limit)
source_dir = "public"      # Source directory to deploy

[[deployment.targets]]
name = "prod"
url = "file:///var/www/mysite"   # Local directory deployment

[[deployment.targets]]
name = "staging"
url = "s3://my-bucket"
command = "aws s3 sync {source}/ {url} --delete"  # Custom command deployment
```

**Implementation details:**
- `src/services/deployer.cr` - Core deployment logic with directory sync, file comparison, and command execution
- `src/models/deployment.cr` - `DeploymentConfig`, `DeploymentTarget`, `DeploymentMatcher` models
- `src/config/options/deploy_options.cr` - Deploy command options
- `src/cli/commands/deploy_command.cr` - Deploy CLI command

**Deploy target types:**
- **Local directory** (`file://` or plain path) - File-by-file sync with MD5 comparison
- **Custom command** - Execute arbitrary shell commands with placeholder expansion (`{source}`, `{url}`, `{target}`)

**Target options:**
- `name` - Target identifier
- `url` - Destination URL or path
- `command` - Custom deploy command (overrides URL-based deployment)
- `include` - Glob pattern for files to include
- `exclude` - Glob pattern for files to exclude
- `strip_index_html` - Remove `index.html` from paths (for object stores)

**Safety features:**
- `max_deletes` limit prevents accidental mass deletion
- `--confirm` flag for interactive confirmation
- `--dry-run` shows planned changes without writing
- Source/destination overlap detection
- Environment variables set for custom commands: `HWARO_DEPLOY_TARGET`, `HWARO_DEPLOY_URL`, `HWARO_DEPLOY_SOURCE`

#### 14. Multilingual Support (i18n)

Hwaro supports building multilingual sites with translation linking and language-specific features.

**Configuration in `config.toml`:**
```toml
default_language = "en"

[languages.ko]
language_name = "한국어"
weight = 2
generate_feed = true
build_search_index = true
taxonomies = ["tags", "categories"]

[languages.ja]
language_name = "日本語"
weight = 3
```

**Content structure:**
```
content/
├── posts/
│   ├── hello.md       # Default language (en)
│   ├── hello.ko.md    # Korean translation
│   └── hello.ja.md    # Japanese translation
```

**Implementation details:**
- `src/content/multilingual.cr` - Translation key generation, language detection, translation linking
- `src/content/seo/tags.cr` - Canonical URLs and hreflang tag generation
- `src/models/config.cr` - `LanguageConfig` class, `multilingual?`, `sorted_languages` methods
- `src/models/page.cr` - `language`, `translations` properties, `TranslationLink` struct

**Key functions:**
- `Multilingual.translation_key` - Derives a canonical key from a page path (strips language suffix)
- `Multilingual.link_translations!` - Links translated pages to each other
- `Multilingual.language_code` - Determines the language code for a page
- `Seo::Tags.canonical_tag` - Generates `<link rel="canonical">` tag
- `Seo::Tags.hreflang_tags` - Generates `<link rel="alternate" hreflang="...">` tags

**Template variables for multilingual:**
- `{{ page.language }}` - Current page language code
- `{{ page.translations }}` - Array of `TranslationLink` objects with `code`, `url`, `title`, `is_current`, `is_default`

**Init with multilingual:**
```bash
hwaro init --include-multilingual en,ko,ja
```

#### 15. Scaffolds

Scaffolds provide pre-configured project templates for `hwaro init`. Three scaffold types are available:

- **simple** (default) - Basic pages structure with homepage and about page
- **blog** - Blog-focused structure with posts, archives, and taxonomies
- **docs** - Documentation-focused structure with organized sections and sidebar

**Usage:**
```bash
hwaro init mysite --scaffold blog
hwaro init mysite --scaffold docs
hwaro init mysite  # defaults to simple
```

**Implementation details:**
- `src/services/scaffolds/base.cr` - Abstract base class defining scaffold interface
- `src/services/scaffolds/simple.cr` - Simple scaffold implementation
- `src/services/scaffolds/blog.cr` - Blog scaffold implementation
- `src/services/scaffolds/docs.cr` - Documentation scaffold implementation
- `src/services/scaffolds/registry.cr` - Registry for scaffold management
- `src/config/options/init_options.cr` - `ScaffoldType` enum and `InitOptions`

**Base scaffold provides:**
- Common templates (header, footer, page, section, 404, taxonomy)
- Base CSS styles
- Navigation template
- Config sections (plugins, pagination, content files, highlight, OG, search, sitemap, robots, llms, taxonomies, feeds, auto includes, markdown, build hooks, deployment)

#### 16. Content Files Publishing

Non-Markdown files in the `content/` directory can be automatically published to the output directory.

**Configuration in `config.toml`:**
```toml
[content.files]
allow_extensions = [".jpg", ".png", ".gif", ".svg", ".pdf"]
disallow_extensions = [".psd", ".ai"]
disallow_paths = ["drafts/**"]
```

**Implementation details:**
- `src/models/config.cr` - `ContentFilesConfig` class with `publish?` method
- `src/content/processors/content_files.cr` - Content file publishing helper module
- Files are copied preserving their directory structure: `content/about/photo.jpg` → `/about/photo.jpg`
- Extension normalization ensures consistent matching (with or without leading dot)
- Path normalization strips `content/` prefix and normalizes separators

#### 17. Syntax Highlighting

Code syntax highlighting with configurable themes via highlight.js.

**Configuration in `config.toml`:**
```toml
[highlight]
enabled = true
theme = "github-dark"      # highlight.js theme name
use_cdn = true             # Use CDN for highlight.js assets
```

**Implementation details:**
- `src/models/config.cr` - `HighlightConfig` class with `css_tag()`, `js_tag()`, `tags()` methods
- `src/content/processors/syntax_highlighter.cr` - Integrates highlighting into markdown processing

**Template variables:**
- `{{ highlight_css }}` - CSS link tag for highlight.js theme
- `{{ highlight_js }}` - JavaScript script tag for highlight.js
- `{{ highlight_tags }}` - Both CSS and JS tags combined

#### 18. Tool Commands

The `hwaro tool` command provides utility subcommands for content management.

**Frontmatter Converter (`hwaro tool convert`):**
```bash
hwaro tool convert toYAML              # Convert all frontmatter to YAML
hwaro tool convert toTOML              # Convert all frontmatter to TOML
hwaro tool convert toYAML -c posts     # Convert in specific directory
```

Implementation:
- `src/services/frontmatter_converter.cr` - `FrontmatterConverter` class with YAML↔TOML conversion
- `src/cli/commands/tool/convert_command.cr` - CLI command

**Content Lister (`hwaro tool list`):**
```bash
hwaro tool list all                    # List all content files
hwaro tool list drafts                 # List only draft files
hwaro tool list published              # List only published files
hwaro tool list all -c posts           # List in specific directory
```

Implementation:
- `src/services/content_lister.cr` - `ContentLister` class with filtering and formatted display
- `src/cli/commands/tool/list_command.cr` - CLI command

**Dead Link Checker (`hwaro tool check`):**
```bash
hwaro tool check                       # Check all external links in content/
```

Implementation:
- `src/cli/commands/tool/check_command.cr` - Finds external URLs in markdown files and checks them concurrently using HEAD requests

#### 19. Build Profiling & Debug

**Build Profiler:**

The `--profile` flag shows detailed timing information for each build phase.

```bash
hwaro build --profile
```

Implementation:
- `src/utils/profiler.cr` - `Profiler` class with phase timing, bar chart rendering, and formatted report output

**Debug Printer:**

The `--debug` flag prints site structure information after build.

```bash
hwaro build --debug
```

Implementation:
- `src/utils/debug_printer.cr` - `DebugPrinter` module that renders a tree view of the site structure (sections, pages, paths)

### Configuration

Configuration is managed through TOML files (`config.toml`). The structure is defined in `src/models/config.cr` with support for:
- Site metadata (title, description, base_url)
- SEO features (sitemap, robots, llms, feeds)
- Search configuration
- Taxonomy configuration
- Plugin configuration
- Build hooks (pre/post build commands)
- Auto includes (automatic CSS/JS loading)
- OpenGraph & Twitter Cards (social sharing meta tags)
- Markdown parser options (safe mode, lazy loading)
- Syntax highlighting configuration
- Content files publishing
- Pagination settings
- Multilingual / language configuration
- Deployment targets and options

#### Markdown Configuration

The `[markdown]` section controls markdown parsing behavior:

```toml
[markdown]
safe = false          # If true, raw HTML in markdown will be stripped (replaced by comments)
lazy_loading = false  # If true, adds loading="lazy" to img tags
```

Options mapped from [markd](https://github.com/icyleaf/markd):
- `safe` (Bool, default: false) - If true, raw HTML will not be passed through to HTML output (replaced by `<!-- raw HTML omitted -->` comments)
- `lazy_loading` (Bool, default: false) - If true, `loading="lazy"` attribute is added to `<img>` tags for performance

Implementation:
- `src/models/config.cr` - `MarkdownConfig` class
- `src/content/processors/syntax_highlighter.cr` - Passes options to `Markd::Options`
- `src/core/build/builder.cr` - `render_page()` uses config's markdown options

#### GFM Table Support

Hwaro includes built-in support for GitHub Flavored Markdown (GFM) tables, since the underlying markd library doesn't support tables natively.

**Table syntax:**
```markdown
| Header 1 | Header 2 | Header 3 |
|----------|:--------:|---------:|
| Left     | Center   | Right    |
| Cell     | Cell     | Cell     |
```

**Alignment options:**
- `---` or `:---` = left align (default)
- `:---:` = center align
- `---:` = right align

**Features:**
- Pipe-delimited columns
- Optional leading/trailing pipes
- Column alignment via colons in separator row
- Escaped pipes (`\|`) within cells
- HTML character escaping in cell content
- Empty cells and rows with fewer columns than headers

**Generated HTML example:**
```html
<table>
<thead>
<tr>
<th>Header 1</th>
<th style="text-align: center;">Header 2</th>
<th style="text-align: right;">Header 3</th>
</tr>
</thead>
<tbody>
<tr>
<td>Left</td>
<td style="text-align: center;">Center</td>
<td style="text-align: right;">Right</td>
</tr>
</tbody>
</table>
```

Implementation:
- `src/content/processors/table_parser.cr` - Table parsing and HTML conversion module
- `src/content/processors/syntax_highlighter.cr` - Integrates table processing before markd rendering

### Extensibility Considerations

The project is designed with extensibility in mind:

1. **Plugin System**: While not fully implemented, the architecture supports:
   - Custom content processors
   - Custom CLI commands via CommandRegistry
   - Custom lifecycle hooks
   - Configurable processors in `config.toml`

2. **Future Extension Points**:
   - Template engine plugins
   - Build optimization plugins
   - Custom SEO generators
   - Search engine backends
   - Asset pipeline processors

3. **User-defined Build Hooks**: Run custom shell commands before/after builds:
   - Pre-build hooks for setup tasks (dependency installation, preprocessing)
   - Post-build hooks for deployment and optimization
   - Implemented in `src/utils/command_runner.cr`

4. **Parallel Processing**: The builder supports parallel content processing with caching for performance optimization

5. **Caching System**: Implemented in `src/core/build/cache.cr` for build optimization:
   - File-based caching to skip unchanged content
   - Cache invalidation based on file modification times
   - Configurable cache enabling/disabling

## Testing

- Tests are organized in `spec/` directory with subdirectories:
  - `spec/unit/` - Unit tests for individual modules and classes
  - `spec/functional/` - Functional/integration tests (asset colocation, CLI, site vars)
  - `spec/content/` - Content processing tests (SEO, etc.)
- Top-level test files: `spec/hwaro_spec.cr`, `spec/lifecycle_spec.cr`, `spec/spec_helper.cr`
- Follow Crystal's testing conventions with `crystal spec`
- Use descriptive test names and organize tests logically

## Common Patterns

### Error Handling

- Use Crystal's exception system
- Provide meaningful error messages through the Logger
- Return result objects for operations that can fail gracefully (e.g., `ProcessorResult`, `ConversionResult`)

### Logging

- Use the `Logger` utility from `src/utils/logger.cr`
- Levels: `Logger.info`, `Logger.error`, `Logger.success`, `Logger.debug`, `Logger.action`, `Logger.warn`, `Logger.progress`
- `Logger.action` for file operations (conditionally shown based on verbose flag)
- `Logger.progress` for progress indicators during deploy and other bulk operations
- Keep user-facing messages clear and actionable

### Type Safety

- Leverage Crystal's strong type system
- Use explicit type annotations for public APIs
- Define structs for data transfer objects (e.g., `ProcessorContext`, `ProcessorResult`, `BuildStats`, `ContentInfo`)
- Use enums for fixed sets of options (e.g., `Phase`, `HookPoint`, `HookResult`, `ScaffoldType`, `ContentFilter`, `FrontmatterFormat`)

### Utility Modules

- `src/utils/sort_utils.cr` - Reusable page sorting utilities (`sort_by_date`, `sort_by_title`, `sort_by_weight`, `sort_pages`)
- `src/utils/text_utils.cr` - Common text operations (`slugify`, `escape_xml`, `strip_html`)
- `src/utils/command_runner.cr` - Shell command execution utility
- `src/utils/profiler.cr` - Build phase timing and reporting
- `src/utils/debug_printer.cr` - Site structure tree visualization

## Dependencies

Current external dependencies (Crystal >= 1.19.0):
- `markd` - Markdown parsing
- `toml` - TOML configuration parsing
- `crinja` - Jinja2 template engine

Keep dependencies minimal and evaluate alternatives before adding new ones.

### CLI Options

Common CLI options across commands:
- `-v, --verbose` - Show detailed output including generated files (default: concise summary)
- `-h, --help` - Show help information

Build-specific options:
- `-o DIR, --output-dir DIR` - Output directory (default: public)
- `--base-url URL` - Override base_url from config.toml
- `-d, --drafts` - Include draft content
- `--minify` - Minify HTML output (and minified json, xml)
- `--no-parallel` - Disable parallel file processing
- `--cache` - Enable build caching
- `--skip-highlighting` - Disable syntax highlighting
- `--profile` - Show build timing profile for each phase
- `--debug` - Print debug information after build

Serve-specific options:
- `-b HOST, --bind HOST` - Bind address (default: 0.0.0.0)
- `-p PORT, --port PORT` - Port to listen on (default: 3000)
- `--base-url URL` - Override base_url from config.toml
- `-d, --drafts` - Include draft content
- `--minify` - Minify HTML output (and minified json, xml)
- `--open` - Open browser after starting server
- `--debug` - Print debug information after build

Init-specific options:
- `-f, --force` - Force creation even if directory is not empty
- `--scaffold TYPE` - Scaffold type: simple, blog, docs (default: simple)
- `--skip-agents-md` - Skip creating AGENTS.md file
- `--skip-sample-content` - Skip creating sample content files
- `--skip-taxonomies` - Skip taxonomies configuration and templates
- `--include-multilingual LANGS` - Enable multilingual support (e.g., en,ko)

Deploy-specific options:
- `-s DIR, --source DIR` - Source directory to deploy (default: deployment.source_dir or public)
- `--dry-run` - Show planned changes without writing
- `--confirm` - Ask for confirmation before deploying
- `--force` - Force upload/copy (ignore file comparisons)
- `--max-deletes N` - Maximum number of deletes (default: 256, -1 disables)
- `--list-targets` - List configured deployment targets and exit

Tool subcommands:
- `hwaro tool convert <toYAML|toTOML>` - Convert frontmatter format
- `hwaro tool list <all|drafts|published>` - List content files by status
- `hwaro tool check` - Check for dead links in content files

Completion command:
- `hwaro completion bash` - Generate bash completion script
- `hwaro completion zsh` - Generate zsh completion script
- `hwaro completion fish` - Generate fish completion script

Installation examples:
```bash
# Bash (add to ~/.bashrc)
eval "$(hwaro completion bash)"

# Zsh (add to ~/.zshrc)
eval "$(hwaro completion zsh)"

# Fish (add to ~/.config/fish/config.fish)
hwaro completion fish | source
```

## Performance Considerations

- The builder uses caching to avoid reprocessing unchanged content
- Parallel processing is implemented for content generation
- File watching in serve mode for automatic rebuilds
- Build profiling available via `--profile` flag for performance analysis
- Be mindful of I/O operations and consider batching when possible
- Deployment uses MD5 comparison to skip unchanged files

## Contributing

When contributing:
1. Follow the established code style and patterns
2. Add tests for new features (in appropriate `spec/` subdirectory)
3. Update documentation as needed
4. Consider backward compatibility
5. Think about extensibility for future features
6. Keep changes focused and atomic

## Future Development Areas

Areas with room for expansion:
- Enhanced plugin system with dynamic loading
- More content processors (AsciiDoc, reStructuredText, etc.)
- Template engine alternatives
- Advanced caching strategies
- Asset pipeline (CSS/JS processing, minification)
- Incremental builds optimization
- Live reload improvements
- Theme system
- Content management helpers
- Advanced search backends (beyond Fuse.js)
- Custom taxonomy types
- Image processing and optimization
- API endpoints for dynamic content
- Remote deployment targets (S3, GCS, Azure Blob via native support)