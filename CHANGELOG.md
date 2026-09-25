# Changelog

## Unreleased

### Security
- `[[data.remote]]` keeps configured headers dropped for the rest of a redirect chain once a redirect leaves the original origin. A third-party host could previously redirect back to the origin and choose which origin URL received the credential.
- Prevent stale output cleanup from deleting files through symlinked directories outside the configured output directory.

### Fixed
- `hwaro build --cache`: remove outputs no longer produced after a generator version change.
- Keep generated `robots.txt` and `404.html` when static files at those paths are removed.
- CLI writers now refuse symlinks that escape their project roots. `init` checks every scaffold destination before writing, so a refused run leaves the target untouched, and keeps existing entries (such as a `templates/` link to a shared theme) without refusing them. Import follows file links within the site directory it is given and skips (and counts) those outside it; export skips links outside the project, while deploy follows links within the project or resolved source root and skips targets outside both. Conversion preserves in-project symlink behavior and skips targets outside the project. `tool agents-md --write` writes through an `AGENTS.md` symlink resolving inside the project (such as `AGENTS.md -> CLAUDE.md`) and refuses one resolving outside it.
- A known `config.toml` section written in the wrong shape (`highlight = false` instead of a `[highlight]` table, `taxonomies = ["tags"]` instead of `[[taxonomies]]` entries) is now reported. It was ignored with no feedback, and so was a `[[taxonomies]]` entry without a `name`. The backward-compatible `sitemap = true` short form is still accepted without a warning.
- Environment variables substituted into a double-quoted `config.toml` string are inserted verbatim: a value with a `"` no longer fails the config load, and a backslash (a Windows path) is no longer re-read as an escape (`C:\new` became a newline). `$VAR` inside a `#` comment is no longer substituted or warned about. Placeholders outside strings (`paginate = ${N}`) still insert raw TOML.
- Every option documented as a list of strings accepts a single string as a one-item list. `[sitemap] exclude = "/private/"`, `[search] exclude`/`fields`, `[feeds] sections`, `[amp] sections`, `[build] hooks.pre`/`hooks.post` and others silently dropped a single string. Private pages stayed in the sitemap and search index, AMP applied to every section, and the hook never ran. An empty string (an unset `${VAR:-}`) still leaves the option unset, and a value that is neither a string nor an array keeps the default with a warning.
- A typo, a mistyped section or a NUL byte in `config.<env>.toml` is reported against that file instead of `config.toml`.
- `[markdown] math_engine` and `[feeds] type` accept any casing (`"MathJax"`, `"Atom"`) and warn about an unknown value. An unrecognised math engine loaded no renderer, so formulas shipped as raw TeX, and an unknown feed type was published as RSS without a word.
- A `[permalinks]` rule whose target is not a string (a number, or a dotted key such as `blog.news = "news"` that TOML reads as a nested table) is reported instead of silently ignored.
- `[og] fb_app_id` accepts an unquoted numeric id. It was dropped, and no `fb:app_id` meta tag was emitted.
- The docs listed `[llms] enabled` as defaulting to `false` (it is `true`) and a language's `taxonomies` as `[]` (it inherits every `[[taxonomies]]` name). They also claimed nested section keys are validated, which they are not.
- Hugo and Jekyll exports now parse JSON front matter, preserving metadata and respecting draft filtering; malformed JSON headers report export errors.
- `tool list`, `tool convert`, `tool check-links`, `tool stats`, `tool validate`, and `tool unused-assets` reject unexpected positional arguments, including arguments after `--`, instead of silently ignoring them.
- Markdown: allow optional whitespace between `:::` and container type name in custom containers.
- Markdown: support case-insensitive alert types in GitHub/Obsidian admonition syntax (`> [!note]`, `> [!tip]`, etc.).
- Importers: support importing standalone root-level and subfolder markdown pages in Jekyll importer.
- Code health: normalize `require` path in HTML filter.
- JS minification: a regex literal after an expression keyword (`return /\/*$/.test(u)`) was read as division, and a `/*` or `//` in its body swallowed the rest of the file, including every later file of the bundle
- JS minification: a `/` inside a regex character class (`/^[^\\/]*\//`) no longer ends the literal early and turns its closing `\//` into a line comment
- CSS minification: dropping a comment between two tokens of a declaration value no longer fuses them (`margin:1px/**/2px` became `1px2px`, and `font:12px/**/Arial` lost its family). Selectors and at-rule preludes are unchanged: `div/**/p` does not become the descendant selector `div p`
- HTML minification: `<link href=/favicon.ico />` no longer becomes `href=/favicon.ico/`. The space before `/>` is kept after an unquoted attribute value
- HTML minification: comments and line-final spaces inside attribute values are left alone (`data-x="<!-- keep -->"` used to become empty)
- Asset pipeline: relative `url(...)` values in bundled CSS are rebased onto the bundle's location when they point at a file beside the source stylesheet in `static/` (`url(img/x.png)` from `static/css/a.css` used to 404 from `/assets/`). Text inside CSS strings and comments is left alone
- SEO: a page-bundle `image = "cover.png"` now resolves to the bundle asset in `og:image`, `twitter:image`, JSON-LD and `seo.og_image`, instead of `/cover.png`
- SEO: the path of a site-relative `og:image`, `twitter:image` and JSON-LD image URL is percent-encoded like `og:url`. A `?query` or `#fragment` is kept as written, and external image URLs are left untouched on all three
- Taxonomies: `render = false` pages no longer appear on term pages, term feeds or `get_taxonomy`, which linked a page that is never written
- Templates: the root `_index.md` now fills `section.pages`, `paginator.pages` and `section.pages_count` with its pages, as `section.list` and `get_section` already did
- Templates: the root `_index.md`'s `section.subsections` now lists the top-level sections. `site.sections` and `get_section` keep the root entry without subsections, and prev/next order is unchanged
- Multilingual: a file with an explicit default-language suffix (`about.en.md`) is now treated like the unsuffixed default. It used to drop out of its section's `section.pages`, and a suffixed `_index.en.md` listed none of its unsuffixed pages
- Feeds: section feeds now include pages from `transparent` subsections, matching the section's `section.pages`
- SEO: `redirect_to` pages are left out of `sitemap.xml`, including its hreflang alternates, RSS/Atom feeds, `search.json` and `llms.txt`
- Series: series are now grouped per language (and per version), so a post and its translation sharing a `series` name no longer interleave into one series with the wrong `series_index`
- Templates: `section.subsections` (and `get_section(...).subsections`) are ordered by `weight` then path, the same order the prev/next chain walks. They used to follow file discovery order
- Section listings no longer show a page whose output lost a duplicate-URL collision, so each URL is listed once
- `build --cache`: retitling a child section's `_index.md` now re-renders the parent section's listing, including the homepage for a top-level section
- `tool check-links`: scan `.markdown` files and match Markdown extensions case-insensitively like the build (`post.MD` is scanned, resolves `/post/`, and counts toward pagination bounds).
- Content tools: include uppercase Markdown files when listing, validating, and collecting asset references.
- `tool validate`: normalize titled and angle-bracket internal links, and report raw HTML `<img>` elements that have no `alt` attribute (`alt=""` is accepted as decorative). HTML comments and indented code blocks are no longer scanned for images or links, matching `tool check-links`.
- `tool platform cloudflare`: generate the Cloudflare Pages `pages_build_output_dir` setting, and point the redirects note at `static/_redirects` (a `public/_redirects` is deleted by the next build).
- `tool check-links` and `tool validate`: resolve `@/` links through the same lookup as the build (exact, case-sensitive content path of a page a default build publishes; no percent-decoding, path normalization or extension/`_index.md` guessing), so links to drafts, `@/UPPER.md` on case-insensitive filesystems, `@/./x.md`, `@/../x` and `@/posts/` are reported instead of passed. `tool validate` now also reports an empty `@/` link.
- TOML: fractional seconds of any precision (`2024-03-05T10:20:30.123Z`) parse instead of failing the build with "expected microsecond digit"
- TOML: an offset date-time keeps its UTC offset, so `date = 2024-03-05T08:20:30+09:00` prints `2024-03-05` like the same value in YAML front matter, instead of the previous day in UTC
- TOML: an out-of-range UTC offset (`+25:00`, `+23:99`) is a parse error, like any other malformed value
- Feeds: an authored midnight with an explicit offset (`2024-03-05T00:00:00+09:00`) keeps its instant in `<pubDate>` / `<updated>`; only a date-only value is re-anchored to UTC midnight
- TOML: a local time (`t = 07:32:00`) is read as that string, instead of being dated to the day the build ran; an out-of-range local time is a parse error instead of a crash
- `tool import hugo`: JSON front matter is read (it used to land in the body); a leaf bundle with `slug` stays a bundle under the slugged directory (or in its own directory, with a warning, when the slug names another bundle); `url` maps to `path`
- `tool import jekyll`: a literal `permalink` maps to `path`, `redirect_from` to `aliases`, `last_modified_at` to `updated`, and `image: {path: …}` to `image`
- Imported `url` / `permalink` values: a `.html` address becomes an extensionless `path` plus an alias, a trailing `index.html` maps to its directory, a query/fragment is dropped, and a URL naming another kind of file is left unmapped with a warning
- `tool export hugo`: `path` maps to `url`
- `tool export jekyll`: `path`, `aliases` and `updated` map to `permalink`, `redirect_from` and `last_modified_at`
- `hwaro build` rejects unexpected positional arguments (`hwaro build mysite`) instead of silently ignoring them and building the current directory.
- `--cache` builds no longer keep publishing files whose source is gone: a deleted `static/` file, a deleted `[content.files]`/raw file, and a page-bundle asset removed from its bundle are now dropped from the output directory, and fingerprinted asset bundles no longer accumulate one stale `main.<hash>.css` per edit.
- `--cache`: a `static/` file that publishes to a page's URL (`static/about/index.html` beside `content/about.md`) no longer replaces that page's rendered HTML on a warm build — the page is re-rendered, exactly as on a cold build where the render runs after the static copy.
- `--cache`: the stale-output prune never deletes a file the build itself wrote, so a `static/robots.txt` or `static/404.html` that shadows a generated file can be removed without taking the generated output with it.
- `--cache`: a `static/` file that lands on an `aliases` redirect stub or a section's `/page/N/` pagination page no longer replaces it on warm builds — those files are written only by a render, so the owning page is re-rendered too.
- `hwaro serve`: a static save that lands on a file a page renders escalates to a full rebuild instead of leaving the static bytes on that URL for the rest of the session.
- `--stream --cache`: warm builds re-render cache-hit page content again, so `search.json`, `rss.xml` and taxonomy feeds no longer ship raw `{% shortcode %}` markup, unresolved `@/` links or un-prefixed subpath URLs.
- A page whose `aliases` entry escapes the output directory is no longer counted in the build receipt's "not published" row or in `--json`'s `pages_not_published`; the page itself published fine. An alias refused for resolving outside the output directory now warns instead of vanishing silently.
- A page bundle whose URL traverses out of the output directory no longer creates a stray directory beside it, and a bundle whose assets are all skipped no longer leaves an empty destination directory.
- A failing `[build] hooks.pre` command now exits with `HWARO_E_CONFIG` (exit 3) and names the hook, instead of the `HWARO_E_INTERNAL` / exit 70 reserved for hwaro's own faults.
- `--full` without `--cache` warns that it has no effect instead of silently doing nothing.
- The asset pipeline no longer leaves an empty `assets/` directory in the output when no bundle is produced.
- The listing-template source memo is keyed by the template snapshot itself rather than its `object_id`, so a reloaded snapshot at a recycled address can no longer serve the previous snapshot's cache-invalidation decisions.
- `hwaro serve` re-renders pages that print a global listing — the homepage's "latest posts", an archive, a nav built from `site.menus`, a tag pill resolved through `get_taxonomy_url` — when an edit moves what that listing reads. Retitling a post used to leave every such page showing the pre-edit title until an unrelated save happened to re-render it. Each kind of listing is gated on a fingerprint of its own inputs, so a post edit refreshes the homepage without dragging every page that merely renders the shared nav into the rebuild.
- `hwaro serve` rebuilds `.markdown` pages on save. They were classified as content assets, whose republish path drops page extensions, so editing one rebuilt nothing at all and the served HTML stayed stale for the whole session.
- `hwaro serve` watches a configured `[assets] source_dir` that lives outside `static/`. Bundle sources there produced no watch event, so a fingerprinted CSS/JS bundle kept serving its pre-edit bytes for the whole session.
- `hwaro serve` answers a non-canonical directory URL (`//posts/`, `/posts//`, `/./posts/`) with a redirect to `/posts/` instead of `/posts/index.html`. The `index.html` rewrite used to leak into the canonicalising redirect, producing a URL the site never links to and no static host emits.
- `hwaro serve` returns 404 for a request path whose percent-escapes decode to invalid UTF-8 (`/%c0%ae%c0%ae/`), matching what a static host does. It previously answered a 302 whose `Location` had every undecodable byte replaced with U+FFFD.
- The serve watch timeline names the config file that actually changed, so an edit to a `config.<env>.toml` overlay is no longer reported as `config.toml`.
- Serve rebuild receipts read "1 page" rather than "1 pages".
- Markdown with a very long single line no longer fails to render with `Regex match error: JIT stack limit reached` (build exit 4). Examples are an HTML tag with tens of thousands of attributes (inline or as a block), a 100k-character HTML comment, a long link label or `<…>` destination, or a run of unclosed link titles such as `[a](b (` repeated thousands of times, including in reference definitions. The affected markd patterns are now possessive or replaced by a linear scanner that returns exactly what the regex did, so ordinary Markdown renders byte-for-byte as before.
- A line of thousands of unclosed inline links (`[a](` repeated) or unclosed link titles now renders in linear time: 32,000 of them take about 40 ms in a release build, where 16,000 took minutes. Every failed link used to entity-decode the whole rest of the line, and markd re-scanned and re-validated it once per bracket.
- Long paragraphs build in linear time. markd copied the whole paragraph for every added line, and re-sliced it after every link reference definition. A paragraph of 20,000 consecutive definitions now renders in 75 ms instead of 7 s (release build).
- A very long email-like autolink (`<a@b.b.b…>`) no longer fails with the same JIT stack error.
- Markdown task lists, custom heading IDs, and heading attributes now work inside blockquotes.
- Markdown extension delimiters no longer rewrite inline-link or reference-definition destinations and titles, or raw HTML tag attributes. Raw `<pre>`, `<script>`, `<style>`, and `<textarea>` blocks and indented code inside list items (at any nesting depth) stay literal to the Markdown extensions; shortcodes still expand inside raw HTML blocks.
- External link policies now handle case-insensitive and single-quoted raw HTML attributes without duplicating `rel`.
- Template `unique` preserves distinct values with different types.
- Template `default` returns its fallback with the fallback's own type (`default(value=0) + 1` is arithmetic; a `none` fallback still renders as an empty string), and passes a non-empty array, map, or object through instead of printing its internal representation. Other non-empty values are still returned as strings.
- Prev/next (`page.lower` / `page.higher`) for pages in a section without an `_index.md` followed the filesystem's directory order, so the chain differed between hosts, and `hwaro serve` re-rendered untouched pages after an edit because its relink saw a different order than the build. Such pages are now ordered like a section's own pages (the default `date` sort, path tiebreak), grouped by section
- `hwaro build --cache` removes the page of a `[[content.generate]]` record that disappeared from its data. Generated pages have no source file, so nothing recorded their output and the page stayed published and deployed on every later warm build.
- `hwaro serve` drops a page's `<!-- more -->` summary once the marker is deleted. The re-parse kept the old marker summary, so every listing showed it instead of the description or automatic excerpt until restart.
- `hwaro serve` refreshes the version switcher (`page.version_links`) and an old version's canonical link when a counterpart in another version is re-slugged, drafted or turned `render = false`. The unchanged version's page kept linking and canonicalizing to a URL that no longer existed.
- `hwaro serve` refreshes translation links (`page.translations`, the language switcher, sitemap hreflang alternates) when one translation is re-slugged or retitled. The other languages' pages, and the edited page's own switcher, kept the old URL and title.
- `hwaro build --cache` removes search outputs the `[search]` config no longer publishes: `search.json` after `single_file = false` or a `filename` change, the `search/` shard directory after `shards = "none"`, and everything once search is disabled.
- `hwaro build --cache` and `hwaro serve` stop publishing sitemap, feed and llms files the config no longer produces: `sitemap.xml` once `[sitemap]` is disabled or renamed, the main feed once `[feeds]` is disabled, a section feed once the section drops `generate_feeds` (including through an incremental serve edit), a language feed once the language stops generating one, and `llms.txt` / `llms-full.txt` once disabled. Only a cold build removed them before.
- `hwaro serve` writes the versioned parent redirect stub (`/docs/` → the latest version's root, `[versions] latest_at_root = false`) as soon as an authored `content/docs/_index.md` is drafted. The incremental rebuild re-rendered only pages whose switcher links moved, not the latest root that gained the alias, and still counted the drafted page as the URL's owner, so `/docs/` returned 404 until a full rebuild.
- `hwaro serve` removes a taxonomy term page (with its feed and pagination pages) once no page carries the term — after the last tagged post is deleted, drafted or re-tagged, or the taxonomy is dropped from `config.toml`. Only a `--cache` full build pruned these before, so a plain serve session kept serving `/tags/<old>/` until restart.
- `hwaro serve` removes an alias redirect stub once the page no longer declares it (or is deleted or drafted), and a section's `/page/N/` file once the section no longer fills that page.
- `hwaro serve` regenerates `404.html` on incremental content rebuilds. It renders the same site-wide listings as every page (a docs sidebar, the nav), but kept printing the pre-edit titles until a full rebuild.
- `hwaro serve` keeps `[amp]` mirrors in step with incremental rebuilds: a re-rendered page keeps its `<link rel="amphtml">`, its mirror shows the edit, and a deleted, drafted or moved page takes its mirror with it.
- `hwaro serve` without `--cache` drops generated outputs a rebuild no longer publishes: the superseded `main.<hash>.css` after every stylesheet save, and the whole `amp/` tree once `[amp]` is switched off.
- `hwaro serve` removes the old output of a page a full rebuild moved (`slug`, `path`, a permalink rule), drafted or turned `render = false`. Any config or data edit, or a file added alongside the edit, runs a full rebuild, and those rebuilds never looked at the previous site's pages. An incremental `render = false` edit removes the page's file too.
- `hwaro serve` removes stale output through one check: a file stays while a page, an alias stub, a static or content-file copy, or anything written by the current rebuild still publishes at that path. A spelling that differs only by case counts as the same path when it is the same file on disk, so on case-insensitive filesystems (APFS, NTFS) an alias, slug or taxonomy renamed only by case keeps its pages, while case-sensitive filesystems still drop the old spelling. A moved or drafted page-bundle page no longer leaves its assets at the old URL unless `[content.files]` publishes them there. When a stale file was covering a `static/` file at the same path, the static copy is restored, as a cold build would publish it.
- `hwaro serve` no longer fails a rebuild with `No such file or directory` when a page moves back into a directory an earlier rebuild pruned (a `slug` edited and then reverted, `render = false` turned back off).
- Shortcode positional arguments retain explicitly empty values in their parameter slots.
- `get_section()` resolves translated section names against the current page language.
- Raw shortcode blocks remain protected when they contain fenced code.
- Identical shortcode templates report errors against their own source files.

### Changed
- A TOML offset date-time keeps its written offset, so date permalink tokens (`:year`/`:month`/`:day`) and year/month grouping now use the written calendar day. A URL built from the old UTC day can move (e.g. `/2024/02/29/` → `/2024/03/01/`); add the old URL to `aliases` to keep it working
- Builds are substantially faster, with byte-identical HTML output: 5000-page listing-heavy corpus −37%, 5000-page blog corpus −14%, the docs site −29%. Small sites are unchanged.
- OG images and generated PNG variants now deflate through zlib instead of stb's bundled compressor. The images are pixel-identical and about 24% smaller, and encoding them is faster — cached OG images stay valid and are not regenerated.
- The sitemap, feed, llms and search files are now recorded in the `--cache` metadata. Rolling back to an older dev binary with the same version number after a `--cache` build can therefore drop those files for one build; they regenerate on the next.

### Added
- Shortcodes: add optional `start` parameter (timestamp in seconds) to built-in `youtube` shortcode (#629).


## v0.20.2

### Added
- Search: opt-in sharded index — `[search] shards` splits `search.json` per section/language with a manifest, plus `single_file` and `content_max_length` (#784)
- Automatic summaries: pages without a `<!-- more -->` marker or `description` get `page.summary` from the first 70 words, tuned by `[content] summary_length`/`summary_ellipsis`; new `page.summary_truncated` (#786)
- `[git]` config: one `git log` per build exposes `page.git` commit metadata and fills a missing `updated`/`date`, so sitemap, feeds and JSON-LD follow the file's real history (#785)
- Versioned documentation: `[versions]` + `[[versions.list]]` publish doc versions side by side with `page.version`, version switchers, scoped navigation, canonical + noindex for older versions (#787)

### Changed
- Internal restructuring for parallel and AI-assisted development: per-concern file splits, a `SECTION_LOADERS` registry, deduplicated pipelines, contributor tooling (`just verify`, `changelog.d/`, `ARCHITECTURE.md`). Generated sites are byte-identical (#790)
- Built-in shortcodes warn when a required argument is missing instead of emitting a dead embed (#791)

### Fixed
- `hwaro build --cache` deletes the output of pages that went away — a deleted, renamed, drafted or expired page kept its HTML, aliases, AMP mirror, OG image, taxonomy term page and pagination pages in `public/`. A warm `--cache` build is now byte-identical to a clean one (#791)
- `--cache`: a page turned `render = false` no longer lingers in `sitemap.xml`, feeds, `search.json` and `llms.txt` (#791)
- `hwaro build --stream` no longer ships raw shortcodes and unresolved `@/` links into feeds and the search index; also drops a second markdown pass per page (#791)
- Custom heading ids may start with a digit: `## 1. 프로젝트 {#1-create-a-project}` sets that id instead of rendering literally, matching hwaro's own auto-slugs (#792, #793)
- Syntax highlighting emits one span per run of same-class tokens — 9.6% fewer spans and 68 KB less HTML on the docs site, and `puts "hi"` reads correctly in search and feed summaries (#791)
- `aria-hidden="true"` elements stay out of plain-text projections — anchor-link 🔗 and code line numbers no longer pollute the search index and excerpts (#791)
- `resize_image().width` reports the chosen variant's actual width instead of the requested one, which never upscales (#791)

## v0.20.1

### Added
- Markdown: admonition custom titles (`> [!NOTE] Custom`) and tables inside blockquotes (#777)

### Fixed
- macOS release tarballs are re-signed after their dylib load paths are rewritten — the v0.20.0 `osx-arm64` binary (and the Homebrew formula built from it) was SIGKILLed at launch on every Apple Silicon Mac (#782, #783)
- `--cache`: warm builds no longer ship raw shortcodes into `search.json`/feeds, and static-copy/data-digest staleness gaps closed (#769, #775, #779, #781)
- Template engine: three build-aborting crashes fixed, and every template error now reports its `file:line:col` (#768, #775, #781)
- `hwaro build` keeps output directories it does not own instead of wiping them, and warns on silently skipped content and unknown config (#780)
- Sass: `@import`/`@forward` module configuration and scope, list interpolation, `color.hwb()` alpha, `map.deep-remove()` keywords (#773, #778, #781)
- Markdown: empty-heading ids, multi-backtick code spans, container closers, code-span restore no longer O(N²) (#771, #779, #781)
- `hwaro serve`: request path restored after index rewrite, bind failures classified (#774, #781)
- `hwaro tool`: `[build] output_dir` honored in platform configs, section feeds gated correctly in `check-links`, named `convert` failures (#770, #781)
- Five `init`/`new`/`doctor` defects found by dogfooding every scaffold; `pwa.display` validated (#772, #776)

## v0.20.0

### Added
- Remote data sources: `[[data.remote]]` in `config.toml` fetches an HTTP(S) endpoint into `site.data.<key>` — format inference (`json`/`toml`/`yaml`/`csv`), `${VAR}` env interpolation, a disk cache with TTL, and `on_error` handling (#753, #759, #763)
- Content generation from data: `[[content.generate]]` turns each record of a `site.data` array into a first-class content page — listings, permalinks, taxonomies, feeds, search, sitemap and OG images all apply; authored files win a contested path (#764)
- `.hwaro/` keeps itself out of version control: hwaro writes a self-ignoring `.hwaro/.gitignore` when creating the workspace (serve output, remote-data cache), and `hwaro init` scaffolds a project `.gitignore` covering the output directory, `.hwaro/`, and `.hwaro_cache.json` (#767)

### Changed
- `hwaro serve` builds into `.hwaro/serve/` instead of the deployable output directory, and `deploy`/`build` refuse dev-marked output — serve output can no longer poison a production build (#758, #762)

### Fixed
- `hwaro serve`: pre-build hooks rewriting identical bytes (`data/`, `templates/`, `static/`, `config.toml`) no longer trigger endless rebuild loops (#757, #760, #765)
- `hwaro doctor` / `tool check-links` no longer validate against a build output directory they cannot trust — absent, stale or serve-written output is refused as evidence and reported as such (#761, #766)
- Five crash paths on the CLI surfaces found by fuzzing (#751)
- Dogfood fixes: JS bundle ASI-safe concatenation, blank taxonomy terms, absolute-URL aliases, AMP `loading` attribute (#748)
- Nix flake repaired — it had never produced a working build (#754)

## v0.19.0

### Added
- Sass: dart-sass parity round — `@extend`, classic `/` division, unit conversion, static `calc()` folding, the `sass:selector` module, `math`/`string`/`list`/`color` gaps, keyword and variadic arguments, nested properties, `@at-root` queries, `@charset`, and dart-style output formatting (#731, #735, #738)
- `hwaro tool`: `check-links` discovers reference-style and raw-HTML links, `list` reports `[pub]`/`[draft]`/`[future]`/`[expired]`, `stats`/`validate` read `[taxonomies]` tables and JSON front matter (#734, #739)
- `hwaro doctor`: SCSS diagnostics — a root `sass/` directory is never scanned, and `.scss` sources ship raw while `[sass]` is disabled (#742)
- Init scaffolds: PWA wiring, multilingual menus, search fixes, Ember polish (#741)

### Changed
- **Breaking (packagers):** minimum Crystal is 1.21 and no build path uses `-Dpreview_mt` (#725)
- **Breaking (rendering):** a page bundle directly under `content/` renders with `page.html` instead of `index.html`, and `{% raw %}` suppresses shortcode expansion inside the block (#722, #725)
- `slugify` turns `/`, `\` and Unicode dashes into `-` instead of deleting them (`/tags/security-xss/`, `#ci-cd`); affected taxonomy URLs and heading anchors move on the next build (#742)
- Builds are 3-5x faster on template-heavy sites: Boehm GC tuned at startup and the render worker count derived from listing fan-out. Output is byte-identical (#727, #728)
- Failure paths moved onto the documented exit-code taxonomy (`init`, `completion`, `build`, `tool`), and `doctor --fix|--approve|--full` exits non-zero when issues remain (#722, #732)
- `hwaro init --scaffold bare` no longer ships taxonomies, search or highlighting; a symlinked output directory is published through instead of replaced (#722, #725)

### Fixed
- **`hwaro deploy` wrote and deleted outside the destination** (symlinks in the target were followed) and **wiped the destination when run before `hwaro build`**. Also fixed: `~` paths, `--target NAME`, `--dry-run` validation, and single-slash scheme typos (`s3:/bucket`) deploying locally (#733)
- Crash and hang audits — ~120 defects across build, serve, tool and init/new/deploy: a long title segfaulting PNG OG generation, a self-referencing YAML anchor overflowing the stack, a long `---` run hitting the regex JIT limit, unbounded Sass loops and selector explosion (#722, #725, #729, #730, #740)
- `hwaro tool list`/`stats` now agree with `hwaro build` about what is published — future-dated, expired and cascade-drafted pages are no longer counted as shipped (#734)
- `hwaro doctor`: false-green board, multilingual page bundles flagged as broken sections, `--fix` silently skipping a symlinked `config.toml`, remote `[og] default_image` reported missing, and `[doctor] ignore` typos silencing nothing (#732)
- Importers/exporters: UTF-8 BOM, destination collisions, symlink cycles, Hugo page-bundle assets, Jekyll `layout:`, and `[taxonomies]` tags dropped on export (#722, #740)
- `{{ pwa_tags }}` escapes interpolated values, and the scaffold search overlay ranks title matches above body matches again (#743)
- Rendering: block shortcodes named after a Jinja keyword, URL helpers mangling `mailto:`/`data:`/`//host`, quoted numeric shortcode arguments, `og:image`/JSON-LD non-http values, the `robots.txt` sitemap path, and the minifier eating `&nbsp;` and descendant combinators (#720, #722)

## v0.18.1

### Added
- Sass color functions: `darken`/`lighten`, `saturate`/`desaturate`, `grayscale`, `complement`, `adjust-hue`, `mix`, `invert`, `opacify`/`transparentize`, `adjust-color`/`scale-color`/`change-color`, the channel getters, and the `sass:color` module. They previously fell through as literal text, emitting invalid CSS (#712)
- `hwaro -v` as a short alias for `--version` (#711)

### Fixed
- A bare `&` in prose no longer swallows every inline construct up to the next `;` in the same block. Entity references now follow CommonMark — a name from the HTML5 list plus a trailing `;`, anything else is literal text. Also fixes a build-aborting `IndexError` on the input `&;` (#717)
- `--cache` invalidates when the hwaro binary changes: cached pages were keyed only on their inputs, so a rendering fix never reached an incrementally-built site until something else happened to change (#717)
- Numeric character references above U+10FFF decode correctly instead of becoming `�` — emoji, CJK Ext B and beyond, math alphanumerics (#719)
- A long numeric character reference in a link destination, link title, or fence info string no longer aborts the build with `ArgumentError`, and a semicolon-less one (`&#38`) stays literal (#719)
- AMP: `<iframe>` sandboxing is origin-aware — same-origin and relative `src`es no longer get `allow-same-origin`, which AMP forbids and which failed validation (#712)
- Multilingual scaffolds: the blog homepage/archives listings and the book sidebar TOC scope to the current language instead of mixing every language's content (#712)
- The shared `alert` shortcode template honors its documented `title` parameter instead of silently dropping it (#712)

### Changed
- Homebrew tap formula auto-publishes after a release build again (#710)

## v0.18.0

### Added
- Built-in Sass/SCSS compilation (`[sass]`) — pure Crystal, no external tools: variables, nesting with `&`, partials via `@use`/`@forward`/`@import`, mixins with `@content`, user `@function`s, control flow (`@if`/`@each`/`@for`/`@while`), SassScript expressions, a curated `sass:math`/`string`/`list`/`map`/`meta` built-in set, `@at-root`, and `@media`/`@supports` bubbling. `static/**/*.scss` compiles to sibling `.css`, bundle entries compile before concatenation, and `serve` recompiles on change. Plain CSS compiles byte-identically; unsupported: `@extend`, color functions, unit conversion, indented syntax, source maps (#700, #706)
- Hugo-style token permalinks: `[permalinks]` values may use `:year`/`:month`/`:day`/`:slug`/`:title`/`:section`/`:filename` (`"posts" = "/:year/:month/:day/:slug/"`); plain values keep directory-remap semantics (#701)
- Custom feed templates: `templates/rss.xml.jinja` / `atom.xml.jinja` override the built-in markup for every feed kind (#701)
- `[links] broken_internal = "error"`: fail the build with one aggregated list of unresolved `@/` links (#701)
- Markdown render hooks for blockquotes and tables (`render-blockquote.html`, `render-table.html`) (#702)
- Taxonomy sorting: per-taxonomy `sort_by`/`reverse` for pages, `terms_sort_by` (`name`/`count`) for the terms list (#702)
- `[highlight] copy = true`: dependency-free copy-to-clipboard button on code blocks, with per-fence `{copy=…}` overrides (#702)
- Fence options `{hide_lines="1 9-12"}` to elide lines and `{name="main.cr"}` for a filename label (#702, #696)
- Opt-in markdown flags: `smart_punctuation`, `containers` (`:::note`), `task_list_classes`, external-link policy (`target_blank`/`no_follow`/`no_referrer`), plus site-wide `insert_anchor_links` (#696)
- Multi-line footnotes and definition lists (#696)
- Unknown top-level config keys now warn with a did-you-mean suggestion instead of being silently ignored (#692)
- Korean documentation at `/ko/` with a language switcher and language-scoped search (#705)

### Changed
- **Breaking:** `[highlight] mode` defaults to `"server"` — code blocks are highlighted at build time (same `hljs-*` classes, theme CSS keeps working) and `{{ highlight_js }}` renders empty. Set `mode = "client"` to restore browser-side Highlight.js; all pages re-render once after upgrading (#702)
- `get_taxonomy().items` is name-sorted by default instead of insertion order; use `terms_sort_by = "count"` for count-descending (#702)
- Terminal output redesigned to a minimal "spark" identity: whitespace-driven layout, no rules or dividers, a single `✦` outcome line. `--json`, `--quiet`, and plain/`NO_COLOR` output are unchanged (#699)
- Scaffolds modernized under Ember: glass mastheads, view transitions, reading progress, active sidebar/nav state, prev-next navigation (#693)
- `markdownify` honors the site's markdown options (safe mode, smart punctuation) instead of bare defaults (#696)

### Fixed
- `hwaro serve` stability audit (29 findings): un-drafting a page during serve publishes it, slug/path edits delete stale output, deleted sections remove their `index.html`, failed rebuilds show the overlay instead of live-reloading a half-built site, and `data/`/`i18n/` are watched (#698, #692)
- `hwaro new` hardening: path traversal via sanitizer-synthesized dots, silently-unrendered hidden paths, unparseable `--date`, dropped extra positional args, and flat pages colliding with an existing bundle (#697)
- Markdown rendering audit: blockquoted fences, indented-code protection, shortcode placeholders in table cells/definitions/footnotes, math delimiters, and `<!-- more -->` splitting (#695)
- Multilingual prev/next builds its reading order per language, so `page.lower`/`page.higher` never cross into another language's tree; equal-weight subsections use the same path tiebreak as top-level sections (#705, #703)
- Sass dart-sass parity audit (~35 fixes): `$=` attribute selectors, escaped characters in selectors and `url()`, structured values through variables, small-number and `round()`/`min()`/`max()` serialization, document order for `@layer`/`@use`/`@import`, `& + &` cross-products, `@at-root` scoping, and module privacy (#707, #708)
- `[auto_includes]` links SCSS-compiled stylesheets (an SCSS-only site previously shipped unstyled) and `.scss` sources feed the `?v=` cache-bust digest (#708)
- Feeds: basename-normalized self URLs, shared URL-collision winner selection across main/section/language/taxonomy feeds, and `OutputGuard` path safety (#703, #708)
- Token permalinks no longer abort the build for dateless pages that never publish (drafts, expired/future, `render: false`) (#703)
- `get_taxonomy` and term feeds exclude draft and preview-only pages, matching the written taxonomy pages (#708)
- Menu `mailto:`/`tel:` URLs stay external instead of being rewritten to `/mailto:…/`; external-link policy honors uppercase schemes (#708)
- Images resize in sRGB color space, fixing darkened edges and thin lines on downscale (#692)
- `hwaro tool platform`: alias extraction skips headless/out-of-window pages so generation no longer fails where the build succeeds (#703)

### Performance
- Server-side syntax highlighting runs in parallel — the Tartrazine shared-state hazards are fixed at the source, with tokenization bounded at 4 slots to avoid GC allocation-lock convoying (#694)

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
