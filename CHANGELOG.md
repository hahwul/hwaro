# Changelog

## v0.15.1

### Fixed
- SEO: `og:type` and JSON-LD schema selection now distinguish page-bundle leaves from section landings. `og_type_for` keyed the `og:type="website"` override off `page.is_index`, but `read_content` sets `is_index = true` for page-bundle leaves (`some/post/index.md`) just as it does for `_index.md` section landings — so on sites authored as page bundles *every* content page rendered `og:type="website"`, ignoring the configured `[og].type`. The override now keys off whether the page parsed into a `Models::Section` (a true section landing), and the homepage is detected by a root-index path check (a new `home?` helper), so per-language homepages (`/`, `/ko/`) stay `website` while one-level bundles like `content/about/index.md` are not mislabeled. The same flawed `is_index && section.empty?` test drove JSON-LD schema selection — a one-level page bundle was served the `WebSite` schema instead of an `Article` — and now routes through the shared `home?` helper (#608, #601).
- Scaffold nav: the section-loop hint comment in the `blog`/base nav no longer leaks a `{% raw %}` delimiter into every generated page. The explanatory prose *named* the tag with a bare `{% raw %}` ("Wrapped in {% raw %} so…"); Crinja has no concept of HTML comments, so it treated that bare tag as a real raw-block open — swallowing the prose after it and leaking the inner `{% raw %}` verbatim into the page source. The prose is reworded to "wrapped in a raw block" so it contains no bare tag; the real `{% raw %}…{% endraw %}` pair around the example is unchanged (#609).

## v0.15.0

### Added
- `hwaro serve`: custom response headers via `--header 'Name: Value'` (repeatable) and `[serve.headers]` config table.
- Shortcodes: full named closer support (`{% alert %}...{% endalert %}`) with mismatch diagnostics and improved unclosed warnings.
- `[og.auto_image] lazy_generate = true`: defer expensive OG PNG/SVG generation during `hwaro serve` (especially effective with `--fast-start`).
- `hwaro init --full-config`: emit verbose recommended config for maximum discoverability.
- New OG image styles: geometric (`split`, `band`, `brutalist`) and modern/production (`artistic`, `hero`, `surreal`, `monument`), each rendered in both PNG and SVG with its own distinct generated background signature (vertical accent rule, inset frame, two-color diagonal gradient, radial spotlight glow, aurora orbs, oversized type). New `[og.auto_image]` options: `secondary_color` for two-tone styles (auto-derived as a complementary HSL tone when omitted), plus `text_panel` and `accent_bars`.
- Responsive content images: when `[image_processing]` is enabled, markdown `![]()` images that have generated width variants are auto-rewritten with `srcset` + `sizes` so browsers pick an appropriate size instead of always loading the full-resolution source (previously the variants were only used via the `resize_image()` template helper) (#587).
- Blog theme: the post template now renders a Related Posts block when `[related]` is enabled (the engine computed `related_posts` but no scaffold surfaced it) (#593).

### Changed
- `hwaro init` / `doctor`: Hybrid config strategy (C). Default `init` now emits a balanced, much shorter config (~67 lines vs ~389). Doctor is less aggressive by default.
- `doctor`: `--fix` performs real corrective fixes only; new `--approve` adds recommended optional sections; `--full` is shorthand for `--fix --approve`. Removed confusing `--minimal` flag.
- Auto OG images now default to PNG instead of SVG. Social platforms (Facebook, X/Twitter, LinkedIn, Slack, Discord, iMessage) do not render an SVG `og:image`, so the previous default silently produced shares with no preview image. PNG generation falls back to SVG automatically when PNG font initialization is unavailable (#583).
- OG images: the thin top/bottom accent bars on the pattern styles (`default`, `dots`, `grid`, `diagonal`, `gradient`, `waves`) are now off by default for a cleaner look (set `accent_bars = true` to restore them); the SVG renderer now honors the `accent_bars` flag, which it previously ignored.

### Fixed
- `hwaro init`/`doctor`: restored multilingual support (`default_language` + `[languages.*]`) and eliminated duplicate `[sitemap]`/`[feeds]` emission after Hybrid C changes.
- `tool check-links`: recognizes assets in `static/` and `public/` (including image-processed outputs), removing false positives.
- Render: `site.sections` Crinja values now expose `weight`, `draft`, `transparent`, `sort_by` etc. (prevents sort/compare crashes in scaffold templates).
- `hwaro new`: `--section` override now properly takes precedence over path-based section inference.
- Multiple authoring UX fixes from real-site testing (multilingual nav, doctor dedup, draft messaging, default `new` dates, social meta fallbacks).
- OG hex colors, HTML minifier, and cache save hardening: 3-digit CSS shorthand hex (`#fff`) and 8-digit alpha hex are now parsed correctly in OG images (shorthand previously rendered as the wrong color); the HTML minifier no longer raises `IndexError` when content contains a literal preserve-block sentinel; and `CacheManager#save` snapshots its entries under the mutex, fixing a thread-safety violation that could corrupt the cache under `-Dpreview_mt` (#568).
- OG images: long titles in the `band` style are capped to the lines that fit the band instead of overflowing invisibly (background-on-background) into the description; PNG generation warns once when page text contains CJK but no `[og.auto_image].font_path` is set (Latin-only fonts otherwise render blank "tofu" boxes); and the Twitter card downgrades from `summary_large_image` to `summary` when a page resolves to no image, avoiding a blank social preview (#569).
- A section's `page_template` is now applied to its child pages. `determine_template` never consulted the parent section, so the documented per-section default template was a no-op and child pages always fell back to `page.html` (which also meant the blog scaffold's `post.html` date/meta block was never used). Explicit page-level templates still take precedence (#570).
- `tool convert`: date-only front-matter values (e.g. `2026-05-20`) keep their calendar day across formats. They were serialized via RFC 3339 in UTC, so in any positive-offset zone (e.g. KST) the day rolled back and a spurious time was grafted on, which then leaked into sitemap/RSS output. Date-only values now serialize as a bare `YYYY-MM-DD` while genuine timestamps still round-trip as RFC 3339 (#571).
- `hwaro build --memory-limit`: a zero limit (`0`, `0G`) and absurdly large values are now rejected with clear messages instead of degrading to a batch size of 1 or surfacing a raw `Arithmetic overflow` (#572).
- Multilingual search: client-side search is now scoped to the current language. `search.json` tags every entry with its `lang`, the scaffolds filter results to the page's `<html lang>`, and the per-language `build_search_index` key is now honored (it was parsed but never consumed), so a Korean visitor on `/ko/` no longer gets mixed `en` + `ko` hits (#575).
- `.html` aliases are written to that exact path instead of a directory. `generate_aliases` appended `/index.html` to every alias, so `/promo.html` became `public/promo.html/index.html`; aliases ending in `.html`/`.htm` now write to the exact file (Hugo-compatible) while pretty aliases (`/old/`) still get an `index.html` (#576).
- Default themes now emit JSON-LD structured data. The build generated `{{ jsonld }}` (Article, BreadcrumbList, FAQ, HowTo, Website, Organization) but no built-in scaffold included it, so the advertised feature produced zero output; `{{ jsonld }}` is now wired into the `<head>` of the simple/blog/docs/book headers (`bare` stays markup-only by design) (#577).
- AMP: disallowed external stylesheets are stripped from generated AMP pages. The converter left every `<link rel="stylesheet">` in place (site CSS plus the highlight.js/KaTeX CDN links), failing AMP validation; non-font-provider stylesheets are now dropped while allowlisted font stylesheets (Google Fonts, Typekit, Font Awesome, …) are kept (#578).
- Multilingual: default-language taxonomy pages are no longer duplicated under the `/<default_language>/` prefix. They were emitted both at the site root (`/tags/`) and again under e.g. `/en/tags/` as orphaned URLs — absent from the sitemap, without a canonical, and missing the cross-language links the root copies carried (#579).
- `blog` scaffold: posts now render with the shipped `post.html` (article layout, publish date, post meta, series navigation). The `posts` section wasn't wired to the template via `page_template`, so every post fell back to the bare `page.html` and showed no date or meta — and edits to `post.html` had no effect (#580).
- Alert shortcode: the body is now rendered as Markdown, so `**bold**`, `` `code` ``, and `[links](…)` inside an alert render as HTML instead of appearing as literal markup (#581).
- Homepage JSON-LD: the homepage now emits `WebSite` structured data instead of an `Article` with an empty `headline` (invalid per Google's Article guidelines); other untitled pages no longer emit an empty-headline Article either (#582).
- `docs` and `book` themes now render the in-page table of contents when a page sets `toc = true`. The `{{ toc }}` data was exposed by the engine but no built-in theme referenced it, so the documented option silently did nothing; the `book` archetype now enables `toc` by default (#584).
- `[highlight] use_cdn = false` now warns at build time when the self-hosted highlight.js assets (`static/assets/js/highlight.min.js` + theme CSS) are missing, instead of silently emitting 404 references and shipping a site with no syntax highlighting (#585).
- `hwaro build --cache`: a no-op rebuild (all pages cached) no longer prints the false "No content found" hint. The hint keyed off pages *rendered* this build, which is 0 when everything is served from cache; it now also requires zero cache hits, so it only fires for a genuinely empty site (#586).
- AMP: self-closing markdown images (`<img … />`) no longer produce an invalid `<amp-img … / layout="fill">` (stray slash mid-tag) that failed AMP validation. The conversion now strips the trailing slash before appending the layout attribute (#588).
- `base_url` with a trailing slash (from `config.toml` or `--base-url`) no longer produces `//` in links, canonical, and OG URLs. The value is normalized (trailing slash stripped) on assignment, so `{{ base_url }}/path` and the sitemap agree; `doctor` still flags/`--fix`es a trailing slash in the config file (#589).
- `hwaro new`: a title or date containing a double quote (e.g. `-t 'My "Quoted" Post'`) is now escaped in archetype-generated front matter, so the new file is valid TOML instead of failing the next build. Tags were already escaped; title/date now match (#590).
- Blog series navigation now orders prev/next by `series_weight` (walking `series_pages` via `series_index`) instead of the section's flat date-ordered neighbours, which mis-ordered chapters, showed prev/next on the first/last chapter, and could link non-series posts (#591).
- Multilingual: root taxonomy term pages now list only the default language's posts. Previously the English `/tags/foo/` page also listed the other languages' posts (translated titles, `/<lang>/` links) — a cross-language leak; the per-language `/<lang>/tags/foo/` pages were already correctly scoped (#592).
- Pagination SEO: theme headers now render `{{ pagination_seo_links }}`, so paginated section/taxonomy pages emit `<link rel="prev">`/`<link rel="next">` (with correct per-language prefixes on multilingual sites). The engine built these links but no scaffold surfaced them (#594).
- Scaffold nav: the dynamic-section-loop example in the `blog`/`simple` nav comment is now wrapped in `{% raw %}` (Crinja executes tags even inside HTML comments, so it was running — emitting hidden malformed `/<lang>/<lang>/…` links on multilingual sites) and the example is corrected to list only the current language's sections via `{{ base_url }}{{ s.url }}` (no doubled `lang_prefix`) (#595).
- Permalinks: a `[permalinks]` entry mapping a path to an empty target (e.g. `"pages" = ""`) now maps everything under that prefix to the site root instead of producing a doubled slash (`//contact/`) (#596).
- Three multilingual/tooling bugs found by dogfooding: (1) on a multilingual site the default language (served at the root) now honors its own `[languages.<default>].taxonomies` list instead of always using the global `[[taxonomies]]` set, and a `[languages.<code>]` block that omits `taxonomies` inherits the global set rather than the hardcoded `["tags", "categories"]`; (2) `tool check-links` skips links inside fenced and inline code so Markdown examples aren't reported as dead links; (3) the Hugo-shortcode migration warning now shows both conversions — self-closing `{{< name >}}` → `{{ name() }}` and paired → `{% name() %}body{% end %}` (#600).
- `base_url` subpath deploys: alias redirects and the PWA manifest/service worker now include the `base_url` path prefix. `generate_aliases` wrote bare-root meta-refresh targets, and the PWA's `start_url`, icon `src`, `precache_urls`, `offline_page`, and navigation fallback all assumed a domain-root deploy, so project-page sites (`https://user.github.io/repo/`) got 404ing redirects and a PWA that launched the wrong origin. A new `Config#base_path` / `with_base_path` helper routes both; domain-root deploys are unaffected (#603).
- Three SEO/tooling bugs found by dogfooding: (1) raw Markdown no longer leaks into `og:description` / `twitter:description` / RSS `<description>` when a post has a `<!-- more -->` summary but no explicit `description` — a new `Page#plain_summary` strips tags, decodes entities, and soft-truncates; (2) JSON-LD can no longer break out of its `<script>` block — `<`, `>`, `&` are escaped as `\uXXXX` so a title containing `<!--<script` can't trigger the script-data-double-escape state (XSS hardening); (3) `check-links` no longer false-positives on Zola-style `@/` links, resolving them against the content root like the build does (#606).
- `hwaro init`/`new`: the front-matter typo hint now suggests the *closest* known key by Levenshtein distance (so `tag` → `tags`, not `toc`), and `sanitize_url_segment` no longer leaves a dangling hyphen when punctuation precedes a file extension (`foo!.md` → `foo.md`, not `foo-.md`) (#607).

### Performance
- Markdown: combined regex passes for common extension sets (task lists, strikethrough, heading IDs, admonitions).
- Shortcodes: fence + inline-code aware pre-filter to skip unnecessary processing on docs pages.
- OG / profiling: base-layer caching, batched yielding, full hook + asset + Markdown timing in `--profile`.
- Streaming: reduced cache invalidation / GC frequency under `--stream` / `--memory-limit`.

## v0.14.2

### Fixed
- Security: the GitHub Action no longer leaks the workflow token into the `hwaro build` environment. The composite action previously defaulted the `token` input to `${{ github.token }}` and the Docker entrypoint exported it as `GITHUB_TOKEN` for the duration of the build, so user-defined pre/post-build hooks could read the workflow token from environment-driven site configuration even on `build_only` runs. The action now only falls back to `github.token` when the run actually deploys (`build_only != 'true'`), masks the value, and the entrypoint scopes the credential to a local `DEPLOY_TOKEN` used only by the OG cache restore and final `git push`; `GITHUB_TOKEN` / `INPUT_TOKEN` are unset before `hwaro build` runs (gh#550).
- Security: `redirect_to` pages no longer escape the configured output directory. A content file whose front-matter `path` traversed upward (e.g. `../../poc`) bypassed the `PathUtils` / `OutputGuard` normalization that regular pages go through and could plant `index.html` outside `output_dir`. The redirect writer now routes through the same `sanitize_path` + `safe_output_path` guard used by `get_output_path` and skips writing entirely if the resolved path is still outside `output_dir` (gh#549).
- Multi-threaded builds: `Hwaro::Utils::FileSafe.mkdir_p` no longer surfaces `Unable to create directory: '...': File exists` when parallel render workers race on shared parent directories (`/ko/development/page1`, `/ko/development/page2`, …). The previous wrapper deferred to Crystal's `Dir.mkdir_p` with a single whole-call retry, but the retry could re-race on a *different* shared parent and the post-hoc `Dir.exists?(leaf)` check returned false because the walk never reached the leaf. The wrapper now walks components itself and absorbs `EEXIST` per component; a 50×64-fiber MT stress test goes from 129 failures to 0.

### Changed
- `hwaro build --minify` actually shrinks HTML now (~-12% on the docs site, 1223 KB → 1077 KB). The flag was deliberately conservative after a past revert — only comments, trailing whitespace, and blank lines were touched — because aggressive minification broke pages. Two longstanding bugs are addressed directly: (1) the protected-tag regex used `<(pre|script|...)>...</(pre|script|...)>` alternation that did not enforce opener/closer pairing, so a `<pre>` could pair with a `</script>` if both appeared on the page; each whitespace-sensitive tag now runs in its own pass, with `<style>` processed before `<script>` so a literal `<script>` string inside CSS can't false-pair with a real `</script>`. (2) Indiscriminate whitespace stripping removed the visible gap between adjacent inline siblings; collapse now classifies both neighbours against an HTML block-level list, so inter-tag whitespace is stripped whenever *either* neighbour is block-level while inline neighbours keep a single space (`<a>x</a> <a>y</a>` stays visually identical). Protected-block placeholders carry their original display class, so a sealed `<pre>` next to a `<div>` is also stripped while a `<code>` between two inline siblings still keeps a space on each side. Runs of whitespace inside tag openings shrink via a byte-level, quote-aware scan (`<a   href="x"   >` → `<a href="x">`), preserving quoted values that contain `>` (`title="x > y"`) and UTF-8 in `alt="안녕 세계"`. Protected blocks cover `<pre>`, `<code>`, `<script>`, `<style>`, `<svg>`, `<math>`, `<textarea>`, and `<noscript>` (gh#411).

### Performance
- OG image generation: pre-render the config-only background fill, optional background-image blit, overlay, style pattern, and top accent bar once into a ~3MB base layer buffer and `memcpy` it into each per-page buffer; only text, logo, and the bottom accent bar are layered per page. The per-page loop is split into a serial cache-check pass and a parallel render pass dispatched through the existing `Hwaro::Core::Build::Parallel` worker pool (the stb bindings have no global state and each worker owns its own pixel buffer and output file). Output is bit-identical to the previous renderer. Measured on a 200-page PNG site: `style="default"` 6056ms → 1345ms (~4.5x), `style="gradient"` 6151ms → 932ms (~6.6x).

## v0.14.1

### Fixed
- Multilingual: `section.pages`, `get_section(...).pages`, `series_pages`, `related_posts`, and the global pages array now expose `translations` on each item. The per-page Crinja value cache was omitting the field, so sibling-navigation templates iterating `section.pages` saw empty translation arrays even when the same page exposed populated translations as `page.translations` (gh#540).
- `page.lower` / `page.higher` are now populated for page bundles. The transform step skipped any page with `is_index = true`, but `ctx.pages` only contains regular files and page-bundle leaves (`index.md`) — section indexes (`_index.md`) live in `ctx.sections`. Page bundles set `is_index` for URL generation, so the filter silently excluded them and left their flat-navigation neighbors always `nil` (gh#539).

## v0.14.0

### Behavior changes
- `hwaro new <path>.md` now honors the path the user typed instead of silently rerouting bare filenames to `content/drafts/`. `hwaro new foo.md` lands at `content/foo.md`; explicit `hwaro new drafts/foo.md` still drops into drafts and marks the file as draft.
- `hwaro new` refuses to run outside a Hwaro project (missing `config.toml`) with `HWARO_E_CONFIG`, matching `hwaro build`'s contract.
- `hwaro build --drafts` no longer includes drafts in `sitemap.xml`, matching the existing behavior of feeds, llms.txt, and the search index.

### Fixed
- `tool list drafts`: column header no longer renders `TitlePath` glued together when the only draft has a short title.
- `tool convert`: round-tripping front matter (TOML↔YAML) no longer strips the blank line between the closing delimiter and the body. Also doesn't invent one when none existed.
- `tool export jekyll`: produce a Jekyll-conventional layout. Dated content lands flat in `_posts/<YYYY-MM-DD>-<slug>.md` (subdirectories used to nest under `_posts/posts/…`, which Jekyll reads as a category hint). Non-dated content like `about.md` / `index.md` / `archives.md` stays at the export root as regular pages instead of being buried in `_posts/`.
- `Logger.progress` no longer emits `\r`-overwriting animation when stdout isn't a TTY (CI logs, pipes, file redirects). Per-step output is suppressed and a single completion line is emitted, so logs stay readable.
- `doctor`: stop reporting niche optional sections (`[pwa]`, `[amp]`, `[build]`, etc.) as missing — `doctor --fix` in its minimal mode wouldn't add them anyway, so the advice was a dead end. Freshly-init'd `bare` sites are now doctor-clean.
- `book` scaffold: emit `[related]` commented (book ships no `[[taxonomies]]`, so the default enabled snippet referenced an undefined taxonomy and tripped doctor on a fresh init).
- All shipped scaffolds (`simple`/`bare`/`blog[-dark]`/`docs[-dark]`/`book[-dark]`) now populate `description` in scaffolded content so freshly-init'd sites pass `tool validate` cleanly.

### Changed
- Build summary: `Generated N pages` → `Generated N content pages` (taxonomy/archive/section index files weren't in the count, and the bare wording misled users diffing against `find public -name '*.html'`).
- `hwaro build` now surfaces a one-line hint when a build produces zero content pages, so empty sites don't deploy silently.
- `hwaro init` now prints a `Tip: update base_url in config.toml before deploying` line so the localhost default doesn't ship unchanged. The inconsistent "Added N optional config section(s)" line was demoted to debug.
- `--env <name>`: the warning when `config.<name>.toml` is missing now names both the env and the file we looked for, and explains the recovery (create the file or fix the typo). Catches the common "shipped localhost build to prod because `--env prdo`" foot-gun.
- `hwaro build` now warns once per page when Hugo-style `{{< … >}}` shortcode syntax is found in content. Hwaro uses Crinja syntax (`{% name(args) %}body{% end %}`); unconverted Hugo shortcodes would otherwise reach Markdown and ship as HTML-escaped literals (`{{&lt; alert &gt;}}`) in the rendered page.
- `[markdown] math = true` and `mermaid = true` now actually render math/diagrams in the browser. Hwaro emits the right wrapper markup (`<span class="math math-*">` for math, `<div class="mermaid">` for diagrams) but didn't load the renderer, so users saw literal TeX (`\(E=mc^2\)`) or DOT source. The default header partials in `simple`/`blog[-dark]`/`docs[-dark]`/`book[-dark]` scaffolds now pull in KaTeX (or MathJax, per `math_engine`) and Mermaid.js from a CDN when the corresponding flag is on. Templates can opt out via `{{ math_tags }}` / `{{ mermaid_tags }}`.
- Importers (Hugo, Jekyll, Obsidian, Hexo, Eleventy, Astro, Notion, WordPress) now strip the imported body's leading `# Title` when it matches the front-matter title, so imported pages don't render two `<h1>` elements (the Hwaro page template renders one from `page.title` already). Same rationale as the existing `hwaro new` behavior (gh#525).
- `tool import obsidian` now resolves `[[Wiki-Link]]`, `[[Wiki-Link|alias]]`, and `[[Wiki-Link#anchor]]` to absolute site URLs (`/posts/note-two/#section`) by pre-scanning the vault for filenames, titles, and `aliases:`. Previously the importer produced `[Note](note)`, which the browser resolved relative to the current page and 404'd. Inline-tag stripping no longer eats URL fragments either.

### Performance
- Multi-threaded build is now enabled by default. All release/dev/CI build paths compile with Crystal's `-Dpreview_mt`, so `hwaro build` actually uses multiple OS threads instead of running every fiber on one core. On a 1000-page site with `CRYSTAL_WORKERS=8` this is roughly **~30% wall-clock faster** (0.39s → 0.28s on an M1 Pro; CPU utilization jumps from ~1 core to ~3 cores). Smaller sites are mostly startup-bound and see little change. Tune the worker count via the `CRYSTAL_WORKERS` env var (default: 4). Spec suite runs under MT in CI to catch fiber-race regressions.
- New `Hwaro::Utils::FileSafe.mkdir_p` wrapper replaces `FileUtils.mkdir_p` in the build hot path. Crystal's stdlib `Dir.mkdir_p` is check-then-create, which races under MT (two workers can both pass `Dir.exists?` and then both `mkdir`, the loser getting `File::AlreadyExistsError`). The wrapper retries once and then verifies the directory exists, which is the post-condition `mkdir -p` semantics already promise.
- Shortcode template cache and the missing-shortcode warning Set are now mutex-protected. Both had check-then-write patterns that race under MT — a shared cache resize during concurrent writes could corrupt the underlying Hash.
- `Hwaro::Models::MarkdownConfig#math_tags` and `#mermaid_tags` plus the matching scaffold header partials skip output entirely when the feature flag is off (cheap fast path that avoids string concat per build).
- `Hwaro::Utils::TextUtils.escape_xml` now short-circuits when no XML-special bytes are present in the input — sitemap/feed/llms.txt URL escaping skips a `String.build` allocation for the common case where escaping isn't needed.
- `related_posts` Crinja value lookup skips the cache mutex entirely when the page has no related posts. The cache key is per-page (unique), so for sites without `[related]` enabled the cache could never hit anyway — the lock acquire was pure overhead.

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
