# Hwaro - Agent Instructions

## Overview
Hwaro is a fast, lifecycle-driven static site generator written in Crystal. It features a sophisticated hook system and a pluggable architecture for content processing.

## Core Architecture
### Directory Structure
- `src/cli/`: Command registry and implementation.
- `src/content/`: Processors (Markdown, HTML), Hooks (SEO, Taxonomies), and Pagination.
- `src/core/`: Build orchestration, Cache, and Lifecycle management.
- `src/models/`: Core data structures (`Page`, `Site`, `Section`, `Config`).
- `src/services/`: Scaffolding, Development Server, and Deployment.

### Architectural Patterns
1. **Lifecycle Hook System**: 8 phases (Initialize, ReadContent, ParseContent, Transform, Render, Generate, Write, Finalize). Modules register `before/after` hooks via `Hookable` interface.
2. **Registry Pattern**: Used for dynamic discovery of Processors, Commands, and Scaffolds.
3. **BuildContext**: A shared state container carrying pages, sections, and metadata across the entire build lifecycle.

## Development Guide
### Extending Hwaro
- **New Processor**: Inherit `Hwaro::Content::Processors::Base`, implement `process`, and register in `Registry`.
- **New Command**: Define `NAME`, `DESCRIPTION`, and `FLAGS` (using `FlagInfo`) in the command class. Register in `src/cli/runner.cr`.
- **New Hook**: Implement `register_hooks(manager)`, then add to `src/content/hooks.cr`.

## Security Patterns
- **HTML/XML output**: Use `Utils::TextUtils.escape_xml(value)` or `HTML.escape(value)`.
- **Inline JavaScript**: Escape `</` → `<\/` in JSON data to prevent `</script>` breakout.
- **TOML front matter**: Always use safe type casts (`.as_s?`, `.as_bool?`, `.as_i?`, `.as_a?`). Never use `.as_s`, `.as_bool`, etc. without nil guard.
- **Crinja filter arguments**: Use `.to_s` instead of `.as_s` for safe conversion.
- **Paths**: Always use `PathUtils.sanitize_path` for user-provided or content-derived paths.

## Performance Patterns
- **Single-pass processing**: Prefer `String.build` with char-by-char iteration over chained `.gsub()` for escaping/stripping.
- **Bounded string operations**: Use `html[pos, n]` instead of `html[pos..]` in loops to avoid O(n) substring allocations.
- **Crinja value caching**: Cache `Crinja::Value` arrays per-section and per-page. Clear caches at all reset points.

## Maintenance & Standards
### Config Change Checklist
When adding or modifying `config.toml` options, update **all** of the following:
1. **Model**: `src/models/config.cr` (property, default, and loader).
2. **Config Snippets**: `src/services/config_snippets.cr` — shared TOML snippets used by both `hwaro init` (scaffold) and `hwaro tool doctor --fix`. Each snippet method accepts `commented` param to switch between scaffold (full docs, real values) and doctor (all commented out) variants.
3. **Scaffolds**: If the option belongs to a scaffold-only section (not in `config_snippets.cr`), update `src/services/scaffolds/base.cr` directly.
4. **Tests**: Update `spec/unit/config_spec.cr` and relevant feature specs.

### Guidelines
- **Logging**: Use `Logger.action` for file operations and `Logger.progress` for bulk tasks.
- **CLI**: Ensure `FLAGS` are correctly defined for automated shell completion generation.

## Testing
- **Unit**: `spec/unit/` for logic and models.
- **Functional**: `spec/functional/` for CLI and integration tests.
- **Content**: `spec/content/` for SEO and processor output validation.

## Documentation Site

The `docs/` directory is a self-contained Hwaro site that builds the project documentation.

### Build & Verify

```bash
bin/hwaro build -i docs    # Build docs site
# Output: docs/public/
```

Always build after changes to verify rendering.

### Directory Structure

- `docs/content/`: Markdown documentation pages.
- `docs/data/sidebar.yml`: Sidebar navigation structure (supports nested groups).
- `docs/templates/`: Jinja2 templates for the docs site.
- `docs/static/assets/css/`: Stylesheets, numbered by load order (`01-variables` → `08-shortcodes`).
- `docs/config.toml`: Docs site configuration.

### Landing Page

The landing page (`/`) uses a **separate template** (`docs/templates/index.html`) with dedicated CSS (`07-landing.css`). The markdown content in `docs/content/index.md` is **not rendered** — all landing content is in the template directly.

### Sidebar

`docs/data/sidebar.yml` supports two item types:
- **Link**: `{ title, url }` — a navigation link.
- **Nested group**: `{ title, items: [...] }` — a collapsible group header with child links (used in Features section).

### Content Conventions

- **Front matter**: Always TOML (`+++`), not YAML (`---`).
- **`weight` field**: Controls page ordering within a section. No duplicates.
- **`toc = true`**: Add to pages longer than ~40 lines for table of contents.
- **Features docs**: Place a config example (`config.toml` snippet) near the top.
- **See Also**: End pages with `## See Also` linking to 2-4 related pages.
- **Full Reference blocks**: Key pages (Pages, Sections, Config) include a "Full Front Matter Reference" or "Full Example" section with a copy-pasteable block of all available fields.

### Docs Site Sections

| Section | Path | Purpose |
|---------|------|---------|
| Start | `content/start/` | Installation, first site, CLI, config |
| Writing | `content/writing/` | Pages, sections, taxonomies, shortcodes, archetypes |
| Templates | `content/templates/` | Syntax, data model, functions, filters |
| Features | `content/features/` | All built-in features (grouped in sidebar) |
| Deploy | `content/deploy/` | Platform-specific deployment guides |
