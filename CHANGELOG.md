# Changelog

## v0.15.3

### Changed
- Homebrew: tap now ships a prebuilt-binary formula; macOS binary pinned to `openssl@3` (was EOL `openssl@1.1`) so it launches on a clean machine (#615)

### Fixed
- Subpath deploys: root-relative content links are prefixed with the `base_url` path, fixing 404s in pages, feeds, and `search.json` (#616)
- Book scaffold: site root index now leads prev/next order; nav links carry `base_url` under subpath deploys (#616)
- Taxonomies: a configured taxonomy always renders its index page, even with zero terms (#616)
- Feeds & search: title-less root index falls back to the site title instead of emitting an empty title (#616)
- Scaffold a11y & safety: skip-to-content link, focus rings, search `aria-label`, AA-contrast dark text, and `| e`-escaped author titles (#616)
- Alert shortcode: translucent accent tint so it's readable on dark scaffolds (#616)
- Parallel render: shortcode templates cached per-worker, fixing an intermittent `HWARO_E_TEMPLATE` race (#619)
- `hwaro new`: bundle bare paths no longer collapse to `index.md`; `--section` path handling improved (#617)
- `hwaro init`: remote scaffolds without `config.toml` fall back to a generated config; MT-safe directory creation (#617)

## v0.15.2

### Added
- `[static]` config: filter which `static/` files get published — built-in cruft denylist (`.DS_Store`, `.git/`, etc.), `exclude` glob patterns, and `use_default_excludes = false` to opt out (#611)

### Fixed
- Static files: hidden dot-paths (e.g. `.well-known/`) now published in cached (`--cache`) builds, matching cold builds (#610)

## v0.15.1

### Fixed
- SEO: `og:type` and JSON-LD schema now distinguish page-bundle leaves from section landings, so bundle sites no longer label every page `website`/`WebSite`; a new `home?` helper detects homepages (#608, #601)
- Scaffold nav: nav-hint comment no longer leaks a `{% raw %}` delimiter into generated pages (#609)

## v0.15.0

### Added
- `hwaro serve`: custom response headers via `--header 'Name: Value'` (repeatable) and `[serve.headers]`
- Shortcodes: named closer support (`{% alert %}...{% endalert %}`) with mismatch diagnostics
- `[og.auto_image] lazy_generate = true`: defer OG image generation during `hwaro serve` (great with `--fast-start`)
- `hwaro init --full-config`: emit verbose recommended config for discoverability
- New OG styles (`split`, `band`, `brutalist`, `artistic`, `hero`, `surreal`, `monument`) in PNG and SVG; new `secondary_color`, `text_panel`, `accent_bars` options
- Responsive content images: markdown images with width variants auto-rewritten with `srcset`/`sizes` when `[image_processing]` is on (#587)
- Blog theme: post template renders a Related Posts block when `[related]` is enabled (#593)

### Changed
- `hwaro init`/`doctor`: hybrid config strategy — `init` emits a much shorter config (~67 vs ~389 lines); doctor less aggressive by default
- `doctor`: `--fix` does corrective fixes only; new `--approve` adds optional sections; `--full` = `--fix --approve`; removed `--minimal`
- Auto OG images default to PNG instead of SVG (social platforms don't render SVG `og:image`), falling back to SVG (#583)
- OG images: pattern-style accent bars off by default (`accent_bars = true` to restore); SVG renderer now honors the flag

### Fixed
- `hwaro init`/`doctor`: restored multilingual support and removed duplicate `[sitemap]`/`[feeds]` emission
- `tool check-links`: recognizes assets in `static/`/`public/`, removing false positives
- Render: `site.sections` Crinja values expose `weight`, `draft`, `transparent`, `sort_by`, etc.
- `hwaro new`: `--section` takes precedence over path-based inference
- Authoring UX fixes (multilingual nav, doctor dedup, draft messaging, default `new` dates, social meta fallbacks)
- OG hex colors (3-/8-digit), HTML minifier `IndexError`, and `CacheManager#save` mutex hardening (#568)
- OG images: `band`-style long titles capped to fitting lines; CJK-without-font warning; Twitter card downgrades to `summary` when imageless (#569)
- Section `page_template` now applied to child pages; explicit page templates still win (#570)
- `tool convert`: date-only values keep their calendar day across formats; timestamps still round-trip as RFC 3339 (#571)
- `hwaro build --memory-limit`: zero and absurd values rejected with clear messages (#572)
- Multilingual search: scoped to the current language via per-entry `lang` (#575)
- `.html` aliases write to the exact path; pretty aliases still get `index.html` (#576)
- Default themes emit JSON-LD — `{{ jsonld }}` wired into simple/blog/docs/book `<head>` (#577)
- AMP: disallowed external stylesheets stripped; allowlisted font stylesheets kept (#578)
- Multilingual: default-language taxonomy pages no longer duplicated under `/<default_language>/` (#579)
- `blog` scaffold: posts render with `post.html` instead of falling back to `page.html` (#580)
- Alert shortcode: body renders as Markdown (#581)
- Homepage JSON-LD: emits `WebSite` instead of an empty-headline `Article` (#582)
- `docs`/`book` themes render the in-page TOC when `toc = true`; `book` archetype enables it by default (#584)
- `[highlight] use_cdn = false` warns when self-hosted highlight.js assets are missing (#585)
- `hwaro build --cache`: fully-cached rebuild no longer prints the false "No content found" hint (#586)
- AMP: self-closing markdown images no longer emit an invalid `<amp-img … / layout="fill">` (#588)
- `base_url` trailing slash no longer produces `//` in links/canonical/OG URLs (#589)
- `hwaro new`: double quotes in title/date escaped in generated front matter (#590)
- Blog series navigation orders prev/next by `series_weight` (#591)
- Multilingual: root taxonomy term pages list only the default language's posts (#592)
- Pagination SEO: headers render `{{ pagination_seo_links }}` (`rel="prev"`/`"next"`) (#594)
- Scaffold nav: dynamic-section-loop example wrapped in `{% raw %}` and scoped to the current language (#595)
- Permalinks: empty `[permalinks]` target maps to the site root instead of `//contact/` (#596)
- Multilingual/tooling: per-language `taxonomies` honored; `check-links` skips code spans; Hugo-shortcode warning shows both conversions (#600)
- `base_url` subpath deploys: alias redirects and PWA manifest/service worker include the path prefix via `Config#base_path` (#603)
- SEO/tooling: `Page#plain_summary` keeps raw Markdown out of descriptions; JSON-LD escapes `<>&`; `check-links` resolves `@/` links (#606)
- `hwaro init`/`new`: typo hint suggests the closest key (`tag`→`tags`); `sanitize_url_segment` drops dangling hyphen before extensions (#607)

### Performance
- Markdown: combined regex passes for common extension sets
- Shortcodes: fence + inline-code aware pre-filter
- OG / profiling: base-layer caching, batched yielding, full timing in `--profile`
- Streaming: reduced cache invalidation / GC frequency under `--stream`/`--memory-limit`

## v0.14.2

### Fixed
- Security: the GitHub Action no longer leaks the workflow token into `hwaro build`; the credential is scoped to a deploy-only `DEPLOY_TOKEN` (gh#550)
- Security: `redirect_to` pages can no longer escape `output_dir` via a traversing front-matter `path` (gh#549)
- Multi-threaded builds: `FileSafe.mkdir_p` no longer raises `File exists` when workers race on shared parent directories

### Changed
- `hwaro build --minify` now actually shrinks HTML (~-12%): per-tag protected passes, block-vs-inline whitespace collapse, quote-aware tag-opening shrink (gh#411)

### Performance
- OG image generation: shared base layer `memcpy`'d per page with a parallel render pass; bit-identical output, ~4.5–6.6x faster on a 200-page site

## v0.14.1

### Fixed
- Multilingual: `section.pages`, `series_pages`, `related_posts`, and the global pages array now expose `translations` per item (gh#540)
- `page.lower`/`page.higher` now populated for page bundles (gh#539)

## v0.14.0

### Behavior changes
- `hwaro new <path>.md` honors the typed path instead of rerouting bare filenames to `content/drafts/`
- `hwaro new` refuses to run outside a Hwaro project (`HWARO_E_CONFIG`)
- `hwaro build --drafts` no longer includes drafts in `sitemap.xml`

### Fixed
- `tool list drafts`: `TitlePath` header no longer glued together for short titles
- `tool convert`: TOML↔YAML round-trip preserves (and doesn't invent) the delimiter/body blank line
- `tool export jekyll`: dated content lands flat in `_posts/<YYYY-MM-DD>-<slug>.md`; non-dated pages stay at the root
- `Logger.progress` emits a single completion line instead of `\r` animation when stdout isn't a TTY
- `doctor`: stop reporting niche optional sections as missing; `bare` sites are doctor-clean
- `book` scaffold: `[related]` shipped commented out (no taxonomies to reference)
- All scaffolds populate `description` so freshly-init'd sites pass `tool validate`

### Changed
- Build summary: `Generated N pages` → `Generated N content pages`
- `hwaro build` hints when a build produces zero content pages
- `hwaro init` prints a `Tip: update base_url` line; "Added N optional config section(s)" demoted to debug
- `--env <name>`: missing-`config.<name>.toml` warning names the env and file and explains recovery
- `hwaro build` warns once per page on Hugo-style `{{< … >}}` shortcode syntax
- `[markdown] math`/`mermaid` now render in-browser — headers pull KaTeX/MathJax and Mermaid.js from a CDN; opt out via `{{ math_tags }}`/`{{ mermaid_tags }}`
- Importers strip the body's leading `# Title` when it matches the front-matter title (gh#525)
- `tool import obsidian` resolves `[[Wiki-Link]]`, `|alias`, and `#anchor` to absolute URLs

### Performance
- Multi-threaded build on by default (`-Dpreview_mt`): ~30% faster on a 1000-page site (`CRYSTAL_WORKERS=8`); tune via `CRYSTAL_WORKERS`
- New `Utils::FileSafe.mkdir_p` survives the check-then-create race under MT
- Shortcode template cache and missing-shortcode warning Set are mutex-protected
- `MarkdownConfig#math_tags`/`#mermaid_tags` and header partials skip output when the flag is off
- `TextUtils.escape_xml` short-circuits when no XML-special bytes are present
- `related_posts` lookup skips the cache mutex when the page has no related posts

## v0.13.1

### Fixed
- Homebrew tap name in install docs (#517)
- Ruby interpolation in published formula's `test` block (#518)

## v0.13.0

### Added
- JSON front matter support and `hwaro tool convert` for TOML↔JSON / YAML↔JSON, plus `front_matter_format = "json"` for `hwaro new` (#457)
- Structured page index in `llms.txt` per llmstxt.org spec (#506)
- Nested `[extra.*]` subtables in front matter (#476) and data subdirectories as nested iterable maps (#471)
- `doctor` warns on missing config file paths (#505) and detects malformed front matter in content (#441)
- `--clean` flag for `hwaro init` to wipe target before scaffolding (#402)
- Ameba lint integration (#398)

### Changed
- Preserve cause and page context in template errors; convert `ArgumentError` on attribute access to a labeled `UndefinedError` (#501)
- Optimize Docker build caching and image size (#456)
- `help <command>` now delegates to the command's `--help`
- Updated logo and CLI banner (#434)

### Fixed
- Multilingual: hide lang-switcher and emit hreflang in sitemap (#508)
- Build: suppress "Build complete!" on render failures (#507); log summary when drafts are excluded (#415)
- Shortcodes: nested block placeholders (#502), inline `<code>` opacity (#500), missing-shortcode HTML comment (#498), positional args (#496), unknown direct-call warnings (#412), HTML-comment placeholder to avoid stray `<p>` (#475)
- Templates: populate pages/subsections in `get_section()` (#499); dedupe identical errors across pages (#414)
- `tool check-links` / `unused-assets` false positives (#504)
- `page.summary` rendered to HTML, plain-text in `search.json` (#503)
- Authors taxonomy listing pages (#497)
- RFC 822 `pubDate` and TOML datetime literal in scaffolds (#494)
- Preserve KaTeX inline delimiters past Markd parsing (#493)
- Flatten `[extra]` subtable into `page.extra` (#474)
- `hwaro new`: sanitize URL-unsafe path characters (#470), validate/normalize path (#425), keep path on `-s` conflict (#428), avoid double-wrapped bundles (#427), classify under `HwaroError` taxonomy (#426), `--json` payload on success
- `hwaro init`: bare scaffold and `--list-scaffolds` in `--help` (#467), scaffold-aware multilingual content (#401), validate languages and fail on empty remote (#399)
- `tool` errors: usage classification (#469), `tool export --help` lists supported targets (#468)
- Import: summarize unconverted constructs (#455), WordPress `<pubDate>` and table conversion (#454), preserve categories as taxonomy (#453), Obsidian YAML array flattening (#452), error classification with `--force` (#451)
- Doctor: narrow rescue and atomic write in `--fix` (#442); exit non-zero on errors (#440)
- Deploy: reject unknown placeholders in command templates (#435); classify failures under `HwaroError` (#433)
- Serve: ignore editor backup/swap files (#417); reorder banners behind successful bind (#416)
- Validate `base_url` scheme and host at load/CLI time (#413)
- Restore trailing-whitespace strip in minifier and align help text (#410)

## v0.12.1

### Fixed
- `InternalLinkResolver` dropping `base_url` path prefix on `@/` links, causing 404s on subpath deployments (#397)

## v0.12.0

### Added
- Leaf-bundle layout for `hwaro new` with `--bundle`, archetype, and config support (#391)
- Scaffold `archetypes/default.md` on `hwaro init` (#388)
- Configurable front matter with description default for `hwaro new` (#387)
- `--json` output for `build`, `serve`, `deploy`, and `tool` subcommands (#372)
- Per-target summary in `hwaro deploy --json` (#377)
- JSON introspection for scaffolds, archetypes, and deploy targets (#368)
- Stable error taxonomy with consistent exit codes (#373)
- `HwaroError` classification for IO, network, template, and content errors (#378, #380)
- Global `--quiet` flag and `NO_COLOR` support (#371)
- Live reload enabled by default for `hwaro serve` (#370)
- Deterministic ready signal from `hwaro serve` (#367)
- Closest-match suggestion on unknown command/subcommand (#366)
- Configured deploy targets shown in `deploy --help` (#364)
- Inline status glyphs in doctor output (#365)
- Crystal 1.20 support (#342)
- Docs coverage for remaining CLI flags, config keys, template helpers, `tool import`, `serve --no-error-overlay`, and `check-links` filename (#392, #393)

### Changed
- `hwaro new` is flag-only; dropped interactive title prompt (#369)
- Skip image reprocessing for unchanged sources on serve rebuilds (#390)
- Top-k related posts and combined CSS structural-char pass (#382)
- Raise `HwaroError(HWARO_E_CONFIG)` at config-load source (#379)
- Switch CI to official `crystallang/crystal` image
- Expanded unit and functional specs across scaffolds, build phases, lifecycle, pagination, content processors, image hooks, live reload, and tool subcommands (#338, #339, #340, #341, #343, #344, #345, #346, #347)

### Fixed
- Broken check-links URL and missing OG image alt text in docs (#394)
- Scaffold sample dates and broken docs links (#383)
- Always emit `date` field in `tool list --json` (#376)
- Spurious `feeds.filename` doctor warning (#363)
- Interactive prompt hang in non-TTY environments for `hwaro new` (#362)
- Stray dots in `init` output for current directory (#361)
- IPv6 loopback allowlist in `LiveReloadHandler`

## v0.11.1

### Added
- Nix flake environment for development and packaging
- Nix installation guide to docs
- Tests for i18n filters, shortcode nesting, and deployer helpers

### Changed
- Improve AGENTS.md with missing sections and compressed structure
- Update showcase examples in landing page

### Fixed
- SSRF, CRLF injection, integer overflow, and CSWSH security vulnerabilities
- Integer overflow and memory leak in image processor
- `serve -p` flag not reflecting in `base_url` when `--base-url` is unset

## v0.11.0

### Added
- `book` and `book-dark` scaffold types with sidebar navigation (#320)
- Cross-section flat navigation (`page.lower`/`page.higher`) like mdBook/Docusaurus (#321)
- `tool stats`, `tool validate`, `tool unused-assets`, `tool export` commands
- Incremental OG image generation with content-hash caching
- Scaffold preview screenshots and `preview_gallery` shortcode in docs

### Changed
- Refactor `doctor` command alongside new tool subcommands
- Update CLI docs and completion specs for new tool subcommands
- `page.lower`/`page.higher` now follows flat reading order across sections

### Fixed
- Deploy failure on large sites by suppressing git commit output
- Unprocessed template variable in book scaffold content
- Prev arrow overlapping sidebar when open
- Sidebar flash on load in book scaffold
- APK build failures (tracedeps, strip, CARCH for cross-arch packaging)
- AUR publish workflow failures

## v0.10.1

### Added
- `doctor.ignore_rules` config option to suppress known doctor issues (#318)
- Alpine APK package build workflow (#311)
- RPM package build workflow
- AUR package and auto-publish workflow
- APK, DEB, RPM, and AUR installation methods to docs

### Changed
- Optimize `.deb` build by reusing prebuilt release binaries (#310)
- Use ARM native runners for CI Docker build instead of QEMU emulation (#309)
- Improve GHCR build performance: fix cache scope and parallelize platforms (#308)
- Rename AUR package from `hwaro-bin` to `hwaro`

### Fixed
- 19 bugs across core, content, services, and utils modules (#319)
- Config double parsing and doctor self-report issue
- Various packaging workflow fixes (descriptions, indentation, fail-fast)

## v0.10.0

### Added
- `--include-future` flag for `build`/`serve` to include future-dated content (excluded by default)
- `feeds.full_content` option to control RSS/Atom feed content output (full HTML vs summary)
- Block shortcode syntax without parentheses (`{% name key="val" %}body{% end %}`)
- Category grouping to `tool` help output for better readability (#300)
- Duplicate slug detection with warnings during render phase
- `{{ hreflang_tags }}` and `{{ page_language }}` template variables for multilingual support
- 97 unit tests covering edge cases across 7 spec files (#282)

### Changed
- Enable footnotes, task lists, and definition lists Markdown extensions by default (#292)
- Skip future-dated content by default, consistent with Hugo/Zola behavior (#291)
- Update landing page design with ember particle effect and showcase cards

### Fixed
- XSS via front matter injection in templates (`page.title`, `site.title`, `page.description`) (#295, #296)
- HTML tag stripping in search index titles to prevent script injection (#287)
- `search.json` URLs missing `base_url` path for subpath deployments (#298)
- Infinite loop in `preprocess_definition_lists` with empty term (#285)
- Empty page title producing ` - Site Name` instead of `Site Name` in `<title>` tag (#288)
- Deduplicate URLs in sitemap, search index, and RSS feed generation
- Incremental rebuild not respecting `--include-expired` and `--include-future` flags

## v0.9.1

### Changed
- Upgrade snapcraft base from core20 to core24

### Fixed
- Fix concurrency bugs, ReDoS, and I/O error handling

## v0.9.0

### Added
- Notion, Obsidian, Hexo, Astro, and Eleventy importers for `tool import`
- Unified `CacheManager` for centralized cache layer management
- `logo_position` option for auto OG image generation
- Unit tests for TextUtils, SortUtils, Sitemap, and ConfigSnippets

### Changed
- Optimize incremental rebuild to skip unchanged content parsing
- Improve serve mode incremental rebuild with debounce and simplified strategy
- Unify config snippets as single source of truth for doctor detection
- Extract shared logo_coordinates helper and eliminate magic numbers

### Fixed
- robots.txt merging bug and remove GPTBot from defaults
- Obsidian syntax bugs and Eleventy merge issues
- Debounce race condition and order-aware merge in serve rebuild

## v0.8.0

### Added
- AGENTS.md remote/local content modes and `hwaro tool agents-md` command
- `bare` scaffold type for minimal project initialization
- `pagination_obj` template variable for custom pagination markup
- Structured template variables for TOC and SEO
- `cache_strategy` config option to PWA service worker
- Auto-generated deploy commands for `s3://`, `gs://`, `az://` URL schemes
- `--timeout`, `--concurrency`, `--external-only`, `--internal-only` flags to `check-links` command
- `--date`, `--draft`, `--tags`, `--section` flags to `new` command
- `--cache`, `--stream`, `--memory-limit` flags to `serve` command
- `--skip-og-image` and `--skip-image-processing` flags to `build`/`serve` commands
- `--minimal-config` flag to `init` command with dark theme support
- Show draft content paths when using `--drafts` flag

### Changed
- Promote `doctor` to top-level command (`hwaro doctor`)
- Merge `tool ci` into `tool platform`, add `github-pages` and `gitlab-ci` targets
- Organize CLI flags by logical groups in `init`, `build`, `serve` commands
- Deduplicate SEO URL and image resolution logic
- Optimize serve rebuild for mixed content+template changes
- Skip SEO/search index regeneration when cache has no content changes
- Redesign landing page and restructure docs for readability

### Fixed
- OG image text wrapping for CJK and long words
- Table separator regex and string operations
- Undefined warning for `page.extra` in list contexts
- Doctor `missing_config_sections` for commented sections
- Validate `cache_strategy`, sanitize tags, optimize segments

## v0.7.2

### Fixed
- Resolve loop variables over global functions in Crinja templates (#224)

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
