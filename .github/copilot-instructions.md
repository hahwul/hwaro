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
└── utils/            # Utility modules (logger, etc.)
```

### Key Architectural Patterns

1. **Lifecycle Hook System**: The project uses a sophisticated lifecycle system that allows extensibility through hooks at various build phases. See `src/core/lifecycle/` for implementation.

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

### Configuration

Configuration is managed through TOML files (`config.toml`). The structure is defined in `src/models/config.cr` with support for:
- Site metadata (title, description, base_url)
- SEO features (sitemap, robots, llms, feeds)
- Search configuration
- Plugin configuration

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

3. **Parallel Processing**: The builder supports parallel content processing with caching for performance optimization

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
- Levels: `Logger.info`, `Logger.error`, `Logger.success`, `Logger.debug`
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

## Performance Considerations

- The builder uses caching to avoid reprocessing unchanged content
- Parallel processing is implemented for content generation
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
