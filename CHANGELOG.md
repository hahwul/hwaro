# Changelog

## Unreleased

### Added
- Built-in Sass/SCSS compilation (`[sass]` config) — pure Crystal, no external tools: variables with `!default`/`!global`, nested rules with `&`, partials via `@use` (namespaces, `with (...)` configuration) / `@forward` (`show`/`hide`, `as prefix-*`) / `@import`, mixins with defaults, keyword and variadic args, spreads and `@content`, user `@function`/`@return`, control flow (`@if`/`@else`/`@each`/`@for`/`@while`), SassScript expressions (arithmetic, comparisons, strings/lists/maps; `/` is never division — use `math.div`), a curated built-in function set (`sass:math`/`sass:string`/`sass:list`/`sass:map`/`sass:meta` + legacy globals like `map-get`/`nth`/`if()`), `@debug`/`@warn`/`@error`, `@at-root`, `#{...}` interpolation with full expressions, and `@media`/`@supports` bubbling with expression-aware feature values. Value contexts are lenient — anything that doesn't visibly compute keeps its verbatim text, so valid plain CSS compiles byte-identically — while new syntax (conditions, loop headers, `@return`, `@use ... with`) fails the build with located errors instead of emitting broken CSS. `static/**/*.scss` entries compile to sibling `.css`, `.scss` bundle entries compile before concatenation, and `hwaro serve` recompiles on change with errors in the browser overlay. Still unsupported: `@extend`, color functions, unit conversion, the indented syntax, source maps.
- `hide_lines` fence option (`{hide_lines="1 9-12"}`): elide lines from a rendered code block in server mode. Hidden lines keep their physical line numbers, so a `linenos` gutter shows gaps (unlike Zola, which renumbers) — `hl_lines`/`linenostart` keep targeting physical lines; client mode emits an inert `data-hide-lines` attribute
- `[highlight] copy = true`: copy-to-clipboard button on fenced code blocks via a small inline, dependency-free runtime in `{{ highlight_js }}` (both modes); per-fence `{copy=true|false}` overrides, mermaid fences excluded, byte-identical output when off. New scaffolds enable it
- Markdown render hooks for blockquotes and tables: `templates/hooks/render-blockquote.html` (`text`) and `templates/hooks/render-table.html` (`html`, `header_html`, `body_html`). GitHub-style `> [!NOTE]` blockquotes keep the admonition pipeline while `[markdown] admonitions = true`; the codeblock hook gains `copy`
- Taxonomy sorting: per-taxonomy `sort_by` (`date`/`title`/`weight`) and `reverse` order the pages within each term (section semantics — date is newest-first, `reverse` flips), `terms_sort_by` (`name`/`count`) orders the terms list. Term feeds stay reverse-chronological regardless

- Hugo-style token permalinks: `[permalinks]` values may contain `:year`/`:month`/`:day`/`:slug`/`:title`/`:section`/`:filename` segments that rebuild the whole URL for leaf pages (`"posts" = "/:year/:month/:day/:slug/"`); plain values keep the existing directory-remap semantics, unknown tokens fail the config load, and a dateless page under a date-token pattern fails the build with a fix-it hint (pages that never publish — filtered drafts, expired/future, `render: false` — are exempt)
- `[links] broken_internal = "error"` fails the build (exit code 5) with one aggregated list of every unresolved `@/` internal link — `source.md → @/target (reason)` per line; the default `"warn"` keeps today's log-and-continue behavior
- Custom feed templates: `templates/rss.xml.jinja` / `atom.xml.jinja` override the built-in feed markup for all feed kinds (main, per-section, per-language, per-taxonomy-term) with a precomputed context (absolute encoded URLs, RFC 822/3339 dates, summaries, absolutized HTML); the built-in output remains the fallback when no template exists, and feed-template edits refresh feeds on warm `--cache` builds and `serve` re-renders

### Changed
- **Breaking:** `[highlight] mode` now defaults to `"server"` — code blocks are highlighted at build time (Tartrazine, same `hljs-*` classes, theme CSS keeps working) and `{{ highlight_js }}` renders empty by default. Set `mode = "client"` to restore browser-side Highlight.js; all pages re-render once after upgrading
- `get_taxonomy().items` is now name-sorted (alphabetical) by default instead of unspecified insertion order; set `terms_sort_by = "count"` for count-descending

### Fixed
- Multilingual prev/next: the flat reading order behind `page.lower`/`page.higher` is built per language, so previous/next links never cross into another language's tree (an English page's "next" could previously be its own translation); cold builds and serve-mode incremental relinks share the same partitioning. A language whose section `_index.<lang>.md` is missing falls back to appending that language's pages after its chain
- Equal-weight **subsections** now use the same path tiebreak as top-level sections, so nested prev/next order no longer depends on glob/insertion order
- Copy button: per-fence `{copy=true}` with the global `[highlight] copy` default off now works — the runtime is appended to `{{ highlight_js }}` only on pages that contain an opted-in block; `data-copy` is no longer stamped when highlighting is disabled
- `{hide_lines=…}` is honored on the `render-codeblock` hook path: hidden lines are removed from both `highlighted` and `code` before the template sees them (server mode)
- Global `[highlight] line_numbers` still wraps a fence whose `{…}` options block is present but unrecognized (e.g. `{oops}`)
- Table render hooks saved with CRLF line endings no longer break the emitted HTML block (blank-line collapse handles `\r\n`)
- Mermaid postprocess matches the `language-mermaid` class as a full token only — `language-mermaidjs` and similar prefixes are no longer rewritten into diagram divs
- External-link policy honors uppercase schemes (`HTTPS://…`)
- Menu `mailto:` / `tel:` / other scheme URLs stay external instead of being rewritten to `/mailto:…/`
- `get_taxonomy` / `terms_sort_by = "count"` no longer include draft or unpublished (`--include-future` / `--include-expired`) pages that written taxonomy pages and term feeds omit
- Feeds: `filename = "feeds/rss.xml"` basename-normalizes so the self URL matches the written file; section/language/taxonomy feeds share main-feed URL-collision winner selection; feed output dirs use the same sanitize + OutputGuard path safety as HTML writers
- Summary shortcode fallback still resolves `@/` links and records strict-mode misses (critical for `render: false` pages whose summaries ship in listings)
- `hwaro tool platform`: alias extraction skips headless / out-of-window pages and uses lenient date-token permalinks so platform generation no longer fails where the build would succeed
- Sass: `#{...}` interpolation unquotes string values (dart-sass parity) instead of shipping embedded quotes as invalid CSS; passing a block to a mixin without `@content` is a located error instead of silently dropping the block's styles; a UTF-8 BOM in an imported partial no longer corrupts its first selector; pathological block nesting fails with a located error instead of a process-killing stack overflow; symlink-loop/permission errors during import resolution surface as classified content errors; a `foo.scss`/`foo.css` name collision under `static/` warns instead of silently overwriting
- Sass (dart-sass parity audit): `a[href$=".pdf"]` and other `$=` attribute selectors no longer fail the build (`$` is only a variable sigil when an identifier follows); `--x: { … }` custom properties with a brace-block value are no longer rejected as nested properties; backslash-escaped `}`/`;`/`)` in selectors and `url()` are honored. Computed values keep their structure through variable storage — `map-merge` over a map holding a comma list no longer leaks raw Sass source into the CSS, `append` reports the right `length`, and `#{$x}` with a null `$x` interpolates as nothing instead of the literal text `null`. Numbers below `1e-4` (reachable from ordinary `opacity`/`scale` math) serialize in fixed notation instead of browser-invalid exponent form, `round()` rounds halves away from zero, `min()`/`max()`/`clamp()` return the winning operand's own unit rather than fabricating one, and `1px == 1` is false. Document order is preserved: empty `@layer` blocks survive (they declare cascade order), `@use`d module CSS is spliced where the `@use` is reached instead of hoisted above earlier rules, and plain-CSS `@import` is lifted above style rules so it isn't silently ignored. `& + &` expands the full parent cross-product, at-rules outside a small descriptor set (`@starting-style`, `@container`, future at-rules) keep the parent selector when nested in a rule, and `@at-root .child &` resolves. Also: `not` binds tighter than comparison, `@at-root` no longer leaks assignments to the global scope, `@each` over null iterates once instead of failing the build, `join()` inherits the second list's separator when the first has none, `to-upper-case`/`to-lower-case` map ASCII only, module members prefixed `-`/`_` stay private, `@use … as *` name collisions error instead of silently overwriting, and a keyword argument to a built-in no longer emits garbage or a bogus "undefined variable"
- Sass serve/integration: SCSS entry and bundle sources that resolve outside the project (symlink) are skipped; serve recompiles also reprocess asset bundles so fingerprinted SCSS bundles stay fresh; hand-written sibling `.css` no longer overwrites compiled SCSS output on serve copy; `?v=` digests SCSS partials outside `[auto_includes].dirs`
- `[auto_includes]` links SCSS-compiled stylesheets: the scan projected only source-tree `.css`, so a `static/css/*.scss`-only site rendered no `<link>` at all and shipped unstyled. `.scss` sources now also feed the `?v=` cache-bust digest, so an SCSS-only edit invalidates caches
- Token permalinks: a dateless draft / `render: false` page matching a date-token pattern no longer aborts the build — the error now fires only for pages that actually publish (full builds and serve rebuilds alike)
- Feeds advertise the same page the build writes when two pages collide on one URL (path-sort-first winner, matching `compute_output_url_winners`)
- `[links] broken_internal = "error"` now also catches broken `@/` links that ship via `render: false` pages' `<!-- more -->` summaries embedded in listings

## v0.17.1

### Changed
- Auto OG images redesigned: bundled Space Grotesk + JetBrains Mono with Latin/CJK fallback chains, seven reworked pattern styles, ember default palette (#687)
- Scaffolds refreshed under the ember identity (`simple`/`blog`/`docs`/`book`; `bare` untouched) (#687)
- Documentation site rebuilt on the ember design system: dark-default with light toggle, breadcrumbs/prev-next, server-side highlighting, self-hosted fonts (#685)

### Fixed
- `hwaro serve`: rewriting templates mid-rebuild no longer breaks the served site — snapshot-consistent `{% include %}`/`{% extends %}`, output-format edits re-render, SEO surfaces refresh, atomic-save temp files ignored (#688)
- `hwaro doctor --fix`: hardened against cross-section corruption — `[[array.of.tables]]` headers no longer leak `[sitemap]` state, `--full` is idempotent, `--approve` adds sections while `--fix` normalizes values (#689)
- `hwaro deploy`: hardened against error-swallowing and stale deletes — classified errors under `--dry-run --json`, no stranded deletions, single-pass placeholder expansion, symlink/overlap safety (#690)
- `hwaro tool`: 50+ fixes across `convert`/`export`/`import`, analysis tools, and platform generators — front-matter preservation, zone-bearing dates, false-positive removal, working CI configs; shared `Utils::FrontmatterWriter` (#691)
- `[outputs].sections` scopes `section` output only, not page-level formats
- `--include-future`/`--include-expired` are preview flags: admitted pages render but stay out of sitemap, feeds, search index, llms.txt, and listings
- Canonical/`og:url`/hreflang percent-encode non-ASCII paths, matching feeds/sitemap
- Taxonomy terms (tags/authors/aliases) whitespace-trimmed at parse time
- Auto OG images skip undrawable codepoints (emoji) instead of rendering tofu boxes
- Heading render hook + `{#id .class}` no longer leaves a doubled space
- Fence options reject `linenostart=0` / `hl_lines="0"` instead of clamping to line 1
- Duplicate explicit `{#id}` heading ids warn when renamed (`#dup` → `#dup-1`)
- CLI polish: singular/plural agreement for 1-item counts; clearer `tool convert` / `unused-assets --help` text

## v0.17.0

### Added
- `[outputs]` config: extra per-page/section output formats (`json`, `txt`, `xml`, `csv`) from user `templates/page.<fmt>.jinja` / `section.<fmt>.jinja`, overridable per page via a front-matter `outputs` key (cascades), exposed as `{{ alternate_output_tags }}`, cache-aware under `--cache`
- Markdown render hooks: `templates/hooks/render-{link,image,heading,codeblock}.html` override element rendering (Hugo/Zola-style), no-op when absent; existing `@/`/shortcode/`srcset`/anchor resolvers still run. See [Render Hooks](https://hwaro.hahwul.com/templates/render-hooks/)
- Fenced code block options after the language (`{linenos=true, hl_lines="2-4 7", linenostart=5}`) plus `[highlight] line_numbers`; `mode = "server"` bakes the result at build time, `mode = "client"` emits `data-*` attributes
- Opt-in inline markup behind `[markdown]` flags (off by default): `ins` (`++`), `mark` (`==`), `sub` (`~`), `sup` (`^`)
- Generalized `{#id .class key=val}` attribute blocks on headings and inline images (`[markdown] attributes`)
- First-class menu system (Hugo-style): `[[menus.<name>]]`, per-language overrides, front-matter registration; exposed via `site.menus`/`get_menu()` with an `active_path` filter; `doctor` validates undefined parents and menu names
- `hwaro init --wizard` and `hwaro new` (no `<path>`) open interactive terminal wizards; archetypes gain a `{{ description }}` placeholder
- Scaffold design tokens ("Hwaro Ember" `:root` with `light-dark()` pairs, fluid type/space scales) and a header theme switcher (auto → light → dark, persisted, flash-free) across every styled scaffold
- `just scaffold-previews`: regenerate docs scaffold screenshots headlessly

### Changed
- `hwaro init` initializes immediately with defaults; `--wizard` opens the interactive flow (removed `-y`/`--yes`)
- Terminal output: the remaining commands (`list`/`stats`/`validate`/`check-links`/`deploy`/`export`/`import`/`unused-assets`/`convert`/`platform`/`agents-md`) adopt the ember language and shared glyph set; machine surfaces (`--json`, `serve` ready line, `--version`, exit codes) are byte-for-byte unchanged
- Scaffold design pass across docs/blog/book (~1,600 lines of duplicated dark CSS deleted)

### Removed
- The `blog-dark`, `docs-dark`, and `book-dark` scaffolds — scaffolds follow the OS scheme and ship a manual switcher; pin one permanently with `:root { color-scheme: dark; }` in `css/style.css`

### Fixed
- macOS release binaries shipped as portable `.tar.gz` archives with bundled OpenSSL, dropping the hardcoded Homebrew `openssl@3` dependency
- Shortcodes: Jinja control tags (`{% if %}`, `{% set %}`) in block bodies no longer desync the nesting scan; mixed positional + named args no longer drop the positional value
- PWA service worker: offline→root navigation fallback restored across all three cache strategies
- `llms-full.txt` honors `in_search_index = false`
- Internal `@/` links with a query string or anchor no longer double-escape `&`
- `hwaro serve`: `authors` front-matter edits update the taxonomy incrementally; equal-weight sections keep a stable prev/next order
- `--cache`: deleting a page regenerates the sitemap/feeds/search index even when no surviving page re-rendered
- Parallel builds surface sitemap/feed/search failures instead of exiting 0; closed section-list and shortcode-init fiber-safety gaps under `-Dpreview_mt`
- AMP: `<img>` with `>` inside a quoted attribute value converts without corrupting the markup

### Performance
- Flat N-page sites avoid an O(N²) render cost — section-page arrays and SEO/OG/canonical/JSON-LD strings are built only when the template's static closure can reach them
- Parallel render workers read prewarmed Crinja caches lock-free (`-Dpreview_mt`); taxonomy generation reuses the running Builder instead of a second O(N) Crinja pass
- Markdown skips footnote/definition-list passes when the markers are absent; builds no longer run the markdown pipeline twice (dropped the legacy hook pre-pass)
- JS minification is no longer O(n²) on non-ASCII files (128KB CJK bundle: 59.5s → 9.6ms); HTML minifier compiles protected-tag patterns once at startup
- `--cache`: touched-but-identical files re-hashed once, page-bundle assets no longer recopied, lock-free hit/miss counters; `serve` incremental rebuilds render the affected set in parallel
- 404 page reuses render-phase template vars; `--stream` builds per-worker engines once per run; `load_data()` memoized per file mtime

## v0.16.0

### Added
- Section `[cascade]` front matter: defaults inherited by descendant pages and sections (Hugo-style); nearer cascades and a page's own keys win, `extra`/`taxonomies` merge per key, and cached/serve builds invalidate affected descendants
- `[highlight] mode = "server"`: build-time syntax highlighting via Tartrazine (250+ languages, pure Crystal). Emits Highlight.js-compatible classes (existing hljs themes keep working) and ships zero JavaScript; default stays `"client"`
- Template dependency tracking: editing a template only rebuilds the pages that render it, in `--cache` builds and `hwaro serve`; opt out with `[build] template_deps = false`
- `page.taxonomies` template variable and Zola-style `[taxonomies]` front-matter tables
- OG styles `terminal`, `bauhaus`, `halftone`, plus upgraded `artistic`/`hero`/`surreal` renders
- `hwaro build --jobs N`: cap parallel render concurrency (#655)

### Changed
- Terminal output redesign ("ember" identity): `build`/`serve`/`init`/`new`/`doctor` share one warm visual language — a live status line collapses into an aligned receipt ending on a single ember outcome line; humanized durations. Machine output (`--json`, the `serve` ready line, `--quiet`, `NO_COLOR`/non-TTY) is byte-for-byte unchanged; scripts grepping human stdout should switch to `--json` (#637)
- `init`/`new` scaffolds unified under the ember identity (#624)
- Template errors report `templates/<file>:line:col` with a caret-marked source excerpt instead of an anonymous `<string>` template
- Docs redesign: collapsible sidebar, header search trigger, command-palette

### Fixed
- Security: hardened importers (path traversal, entity DoS), dev-server CORS, and redirect/report sinks (#643); closed symlink-exfil, WS-origin, and `rm_rf` gaps (#623)
- Dogfood sweeps: 40+ correctness fixes across feeds, markdown, SEO, AMP, PWA, scaffolds, permalinks, and tooling (#640, #641); `--cache` listing-page staleness (#642)
- Friends audit: llms/search/feed discovery surfaces, taxonomy SEO registration, feed absolutization, and CJK-capable OG fonts (#648, #650, #651, #652)
- Markdown: fence tracking, pass ordering, code-span/table-cell corruption, math-span emphasis, unquoted YAML dates, and table code-span pipes (#638)
- Taxonomies: `get_taxonomy` slugs match written pages for drafts and non-default-language terms; closed the authors-taxonomy gap
- `slugify` lowercases uppercase Unicode letters (#639); OG cache invalidates when logo/background file contents change; `get_section().pages` honors the section's `sort_by`; `hwaro serve` removes orphaned output when a watched source is deleted
- `tool export jekyll` preserves the `authors` field (#645); `tool unused-assets --delete` honored in JSON mode plus a new `--force` (#647); Astro singular `author` mapped to `authors` on import (#646)
- Latent-bug and stability audits across subsystems: 10+ edge-case fixes (parse-time, falsy bools, minifier overflow, XML CDATA, etc.) (#620, #653)

### Performance
- Render: per-page template hash computed once, O(1) current-page exclusion in section lists, cache bookkeeping skipped when caching is off
- Feeds/search: memoized fallback markdown renders shared between the two surfaces

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
