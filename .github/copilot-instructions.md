# Hwaro - GitHub Copilot Instructions

## Project Overview

Hwaro is a fast and lightweight static site generator written in Crystal. It provides a flexible, extensible architecture for building static websites with support for markdown content, templates, SEO features, and lifecycle hooks.

## Core Architecture

### Directory Structure

```
src/
├── cli/              # Command-line interface and command registry
│   └── commands/     # Individual CLI commands (init, build, serve, new)
├── config/           # Configuration loading and options
│   └── options/      # Command option structs
├── content/          # Content processing domain
│   ├── hooks/        # Lifecycle hook implementations
│   ├── pagination/   # Content pagination logic
│   ├── processors/   # Content processors (markdown, html, etc.)
│   └── seo/          # SEO generators (sitemap, feeds, robots, llms)
├── core/             # Core build orchestration
│   ├── build/        # Builder, cache, and parallel processing
│   └── lifecycle/    # Lifecycle management system
├── models/           # Data structures (config, page, site, section, toc)
├── services/         # Non-build features (init, new, serve)
└── utils/            # Utility modules (logger, command_runner, etc.)
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

# Run tests (when available)
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
2. Define a command class with a `run` method
3. Register it in `CommandRegistry` in `src/cli/runner.cr`
4. Add the require statement

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

#### 8. User-defined Build Hooks

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

#### 9. Auto Includes

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
- `<%= auto_includes_css %>` - CSS link tags only (place in `<head>`)
- `<%= auto_includes_js %>` - JS script tags only (place before `</body>`)
- `<%= auto_includes %>` - Both CSS and JS tags combined

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

### Configuration

Configuration is managed through TOML files (`config.toml`). The structure is defined in `src/models/config.cr` with support for:
- Site metadata (title, description, base_url)
- SEO features (sitemap, robots, llms, feeds)
- Search configuration
- Taxonomy configuration
- Plugin configuration
- Build hooks (pre/post build commands)
- Auto includes (automatic CSS/JS loading)

### Extensibility Considerations

The project is designed with extensibility in mind:

1. **Plugin System**: While not fully implemented, the architecture supports:
   - Custom content processors
   - Custom CLI commands via CommandRegistry
   - Custom lifecycle hooks
   - Configurable processors in `config.toml`

2. **Future Extension Points**:
   - Template engine plugins
   - Custom shortcodes
   - Build optimization plugins
   - Deployment adapters
   - Custom SEO generators
   - Search engine backends
   - Asset pipeline processors

5. **User-defined Build Hooks**: Run custom shell commands before/after builds:
   - Pre-build hooks for setup tasks (dependency installation, preprocessing)
   - Post-build hooks for deployment and optimization
   - Implemented in `src/utils/command_runner.cr`

3. **Parallel Processing**: The builder supports parallel content processing with caching for performance optimization

4. **Caching System**: Implemented in `src/core/build/cache.cr` for build optimization:
   - File-based caching to skip unchanged content
   - Cache invalidation based on file modification times
   - Configurable cache enabling/disabling

## Testing

- Tests are located in `spec/` directory
- Follow Crystal's testing conventions with `crystal spec`
- Main test files: `hwaro_spec.cr`, `lifecycle_spec.cr`
- Use descriptive test names and organize tests logically

## Common Patterns

### Error Handling

- Use Crystal's exception system
- Provide meaningful error messages through the Logger
- Return result objects for operations that can fail gracefully (e.g., `ProcessorResult`)

### Logging

- Use the `Logger` utility from `src/utils/logger.cr`
- Levels: `Logger.info`, `Logger.error`, `Logger.success`, `Logger.debug`, `Logger.action`
- `Logger.action` for file operations (conditionally shown based on verbose flag)
- Keep user-facing messages clear and actionable

### Type Safety

- Leverage Crystal's strong type system
- Use explicit type annotations for public APIs
- Define structs for data transfer objects (e.g., `ProcessorContext`, `ProcessorResult`)
- Use enums for fixed sets of options (e.g., `Phase`, `HookPoint`, `HookResult`)

## Dependencies

Current external dependencies:
- `markd` - Markdown parsing
- `toml` - TOML configuration parsing

Keep dependencies minimal and evaluate alternatives before adding new ones.

### CLI Options

Common CLI options across commands:
- `-v, --verbose` - Show detailed output including generated files (default: concise summary)
- `-h, --help` - Show help information

Build-specific options:
- `-o DIR, --output-dir DIR` - Output directory (default: public)
- `-d, --drafts` - Include draft content
- `--minify` - Minify HTML output
- `--no-parallel` - Disable parallel file processing
- `--cache` - Enable build caching
- `--skip-highlighting` - Disable syntax highlighting

Serve-specific options:
- `-b HOST, --bind HOST` - Bind address (default: 0.0.0.0)
- `-p PORT, --port PORT` - Port to listen on (default: 3000)
- `--open` - Open browser after starting server

## Performance Considerations

- The builder uses caching to avoid reprocessing unchanged content
- Parallel processing is implemented for content generation
- File watching in serve mode for automatic rebuilds
- Be mindful of I/O operations and consider batching when possible

## Contributing

When contributing:
1. Follow the established code style and patterns
2. Add tests for new features
3. Update documentation as needed
4. Consider backward compatibility
5. Think about extensibility for future features
6. Keep changes focused and atomic

## Future Development Areas

Areas with room for expansion:
- Enhanced plugin system with dynamic loading
- More content processors (AsciiDoc, reStructuredText, etc.)
- Template engine alternatives (beyond ECR)
- Advanced caching strategies
- Asset pipeline (CSS/JS processing, minification)
- Incremental builds optimization
- Live reload improvements
- Theme system
- Content management helpers
- Deployment integrations
- Multi-language support (i18n)
- Advanced search backends (beyond Fuse.js)
- Custom taxonomy types
- Content internationalization (i18n)
- Image processing and optimization
- API endpoints for dynamic content
