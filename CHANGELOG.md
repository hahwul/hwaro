# Changelog

## v0.7.1

### Added
- Bundled DejaVu Sans Bold font as fallback for OG image PNG rendering (no system font required)
- `font_path` config option for custom font in OG image generation
- Image processing and LQIP config snippets to init scaffolds and `doctor` command

### Changed
- OG PNG rendering always available thanks to bundled font fallback (custom font > system font > bundled font priority)
- Refactored font loading logic in `OgPngRenderer` for cleaner initialization

## v0.7.0

### Added
- LQIP (Low Quality Image Placeholder) support for image processing
- OG image enhancements: base64 logo embedding, style presets (dots, grid, diagonal, gradient, waves, minimal), background image support
- Native PNG rendering for OG images via stb_truetype + stb_image_write (no external tools required)
- System font auto-detection for OG images (macOS: Helvetica/Arial, Linux: DejaVu/Noto)
- `show_title` option to toggle site name display on OG images
- Image processing and LQIP config to init scaffolds and `doctor` command

### Changed
- Unify config TOML snippets between scaffold and doctor via shared `ConfigSnippets` module
- Cache fonts, logo, and background image data URIs across all pages for OG image generation
- Clamp opacity and `pattern_scale` values to valid ranges in SVG output
- Code refactoring and test improvements

## v0.6.0

### Added
- Image resize support
- AMP support
- PWA support
- Asset pipeline
- Incremental build
- Auto-generate OG image
- Extended structured data
- Series and serial post support
- Related posts recommendation
- Built-in shortcodes
- Content expiry
- Environment-specific configuration
- Environment variable substitution
- `hwaro tool import` for Jekyll, Hugo, etc. migration
- `hwaro tool platform` for config generation
- GitHub Pages deploy workflow generator
- Config health check and auto-fix to `doctor` command
- `blog-dark`, `docs-dark` scaffold themes

### Changed
- Improve CSS minifier and add cache mutex
- Performance improvements and code refactoring

### Fixed
- Path traversal via symlinks in `safe_path?`
- Command and lint fixes

## v0.5.0

### Added
- JSON output support for tool commands
- Markdown extension and i18n support
- Template filters: `unique`, `flatten`, `compact`, `ceil`, `floor`, `inspect`
- Ellipsis and SEO link support for pagination renderer
- CJK bigram tokenization option for search indexing
- Remote scaffold support for GitHub sources
- Search UI and assets to Docs scaffold
- TOML date fields handling as native Time or String

### Fixed
- Escape meta tag values for SEO, improve URL safety
- Security vulnerability fixes

## v0.4.0

### Added
- Streaming build
- Snapcraft installation support

### Fixed
- Unset Git credential helpers in Docker entrypoint

## v0.3.0

### Added
- `hwaro tool doctor` command
- Functional test cases
- Tests for initializer and shortcode processing

### Changed
- Unify front matter parsing and tag generation

### Fixed
- Security issues
- Help message fix

## v0.2.0

### Added
- Live reload support for serve command
- `--profile` flag with per-template profiling
- `--no-error-overlay` flag and error overlay support for serve command
- Cache busting for local CSS/JS resources
- Unit tests for hooks, lifecycle, and CLI

### Changed
- Refactor front matter and add shortcode module

## v0.1.0

- Initial release
