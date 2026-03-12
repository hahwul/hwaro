# Hwaro - Agent Instructions

## Overview
Hwaro is a fast, lifecycle-driven static site generator written in Crystal. It features a sophisticated hook system and a pluggable architecture for content processing.

## Core Architecture
### Directory Structure Highlights
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

### Templates (Crinja/Jinja2)
- **Variables**: `page`, `site`, `section`, `taxonomy`, `paginator`, `site.data`.
- **Shortcodes**: Placed in `templates/shortcodes/`, called as `{{ name(args) }}`.
- **Filters**: Custom filters include `slugify`, `markdownify`, `absolute_url`, `where`, `sort_by`, `group_by`, `truncate_words`, `split`, `trim`, `date`, `jsonify`, `strip_html`, `xml_escape`, `safe`, `default`, `inspect`.
- **Functions**: `get_page`, `get_section`, `get_taxonomy`, `load_data`, `url_for`.
- **Filter registration**: Each filter module in `src/content/processors/filters/` has a `self.register(env)` method called during template environment setup.

### Key Features
- **Incremental Build**: In `serve` mode, Hwaro picks the optimal rebuild strategy:
    - `run_incremental`: Only re-parses changed pages and updates neighbors/taxonomies.
    - `run_rerender`: Re-renders all pages without re-parsing content (for template changes).
    - `copy_changed_static`: Direct copy for static asset changes.
- **Multilingual**: Automatic translation linking via path-based `translation_key`. Supports per-language feeds and search indices.
- **SEO/LLM**: Built-in generation of sitemaps, robots.txt, OpenGraph tags, and `llms.txt` for AI crawler instructions.
- **Asset Colocation**: Supports "Page Bundles" where assets next to markdown files are automatically collected into `page.assets`.

## Security Patterns
When outputting user-controlled data, follow these escaping conventions:
- **HTML attributes**: Use `Utils::TextUtils.escape_xml(value)` or `HTML.escape(value)` — covers `& < > " '`.
- **XML output** (sitemap, feeds): Use `Utils::TextUtils.escape_xml(value)`.
- **Inline JavaScript**: Escape `</` → `<\/` in JSON data to prevent `</script>` breakout (see `search.cr`, `jsonify` filter).
- **OG/Twitter meta tags**: All `content` attributes in `config.cr` meta tag generation are escaped via `escape_xml`.
- **URL attributes**: Use `HTML.escape(url)` for `href`/`src` in generated HTML (see `table_parser.cr`, `internal_link_resolver.cr`).
- **robots.txt**: Sanitize newlines in user-agent and path values with `.gsub('\n', ' ')`.
- **TOML front matter**: Always use safe type casts (`.as_s?`, `.as_bool?`, `.as_i?`, `.as_a?`) matching the YAML parser pattern. Never use `.as_s`, `.as_bool`, etc. without nil guard.
- **Crinja filter arguments**: Use `.to_s` instead of `.as_s` for safe conversion.

## Performance Patterns
- **Crinja value caching**: Cache `Crinja::Value` arrays per-section (`@section_assets_crinja_cache`) and per-page where applicable. Clear caches at all reset points.
- **Precompute strings**: Compute date strings, permalinks once and reuse across flat vars and `page_obj`.
- **Conditional generation**: Skip expensive operations when output is unused (e.g., breadcrumb JSON-LD only when ancestors exist).
- **Single-pass processing**: Prefer `String.build` with char-by-char iteration over chained `.gsub()` for escaping/stripping (see `TextUtils.escape_xml`, `TextUtils.strip_html`).
- **Bounded string operations**: Use `html[pos, n]` instead of `html[pos..]` in loops to avoid O(n) substring allocations.
- **Builder reuse**: Reuse `Core::Build::Builder` instances across taxonomy renders. Pass `prebuilt_vars` to avoid duplicate `build_template_variables` calls for shortcode pages.

## Maintenance & Standards
### Config Change Checklist
When adding/modifying configuration options:
1. **Model**: Update `src/models/config.cr` (property, default, and loader).
2. **Scaffolds**: Update `src/services/scaffolds/base.cr` and `src/services/defaults/config.cr` so `hwaro init` reflects the change.
3. **Tests**: Update `spec/unit/config_spec.cr` and relevant feature specs.

### Guidelines
- **Logging**: Use `Logger.action` for file operations and `Logger.progress` for bulk tasks.
- **CLI**: Ensure `FLAGS` are correctly defined for automated shell completion generation.
- **Performance**: Use `--profile` to identify bottlenecks in build phases.
- **Paths**: Always use `PathUtils.sanitize_path` for user-provided or content-derived paths.

## Testing
- **Unit**: `spec/unit/` for logic and models.
- **Functional**: `spec/functional/` for CLI and integration tests.
- **Content**: `spec/content/` for SEO and processor output validation.
