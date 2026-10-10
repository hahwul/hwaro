# Main builder module for site generation
#
# This is the core build orchestrator that coordinates phase-based modules:
# - Initialize: output dir setup, cache init, config/template loading
# - ReadContent: content path collection
# - ParseContent: frontmatter parsing (sequential/parallel)
# - Transform: site population, taxonomy, related posts
# - Render: template rendering (sequential/parallel/streaming)
# - Generate: SEO files (sitemap, feeds, robots, etc.)
# - Write: 404 page, raw files, assets
# - Finalize: cache save
#
# The Builder uses the Lifecycle system to allow extensibility
# through hooks at various phases of the build process.

require "digest/md5"
require "file_utils"
require "html"
require "set"
require "toml"
require "json"
require "crinja"
require "./cache"
require "./cache_manager"
require "./parallel"
require "./data_disk"
require "./remote_data"
require "./privacy"
require "./csp"
require "./content_generate"
require "./template_deps"
require "./template_loader"
require "./shortcode_processor"
require "./phases/initialize"
require "./phases/read_content"
require "./phases/parse_content"
require "./phases/transform"
require "./phases/render"
require "./phases/output_formats"
require "./phases/generate"
require "./phases/write"
require "./phases/finalize"
require "../../assets/pipeline"
require "../../content/hooks/asset_hooks"
require "../../content/seo/feeds"
require "../../content/seo/sitemap"
require "../../content/seo/robots"
require "../../content/seo/llms"
require "../../content/seo/tags"
require "../../content/seo/jsonld"
require "../../content/seo/pwa"
require "../../content/seo/og_image"
require "../../content/search"
require "../../content/search_ui"
require "../../content/front_matter_schema"
require "../../content/processors/wikilinks"
require "../../content/processors/includes"
require "../../content/pagination/paginator"
require "../../content/pagination/renderer"
require "../../utils/digest_utils"
require "../../utils/html_stats"
require "../../utils/errors"
require "../../utils/file_safe"
require "../../utils/logger"
require "../../utils/profiler"
require "../../utils/text_utils"
require "../../config/options/build_options"
require "../../content/processors/markdown"
require "../../content/processors/template"
require "../../content/multilingual"
require "../../content/versions"
require "../../content/i18n"
require "../../models/config"
require "../../models/page"
require "../../models/section"
require "../../models/toc"
require "../../models/site"
require "../lifecycle"
require "../../utils/debug_printer"
require "../../utils/path_utils"
require "../../utils/crinja_utils"
require "../../utils/html_minifier"
require "../../utils/output_guard"
require "../../utils/redirect_html"

require "./builder/incremental"
require "./builder/serve_sync"
require "./builder/seo_surfaces"

module Hwaro
  module Core
    module Build
      class Builder
        include ShortcodeProcessor

        # Phase modules — each contributes its methods to this class
        include Phases::Initialize
        include Phases::ReadContent
        include Phases::ParseContent
        include Phases::Transform
        include Phases::Render
        include Phases::OutputFormats
        include Phases::Generate
        include Phases::Write
        include Phases::Finalize

        TEMPLATE_EXTENSION_REGEX = /\.(html|j2|jinja2|jinja|ecr)$/

        @site : Models::Site?
        @templates : Hash(String, String)?
        # Template name → source file path (e.g. "page" => "templates/page.html").
        # Lets compiled templates carry their filename so Crinja errors report
        # file:line:col with a source excerpt instead of an anonymous string.
        @template_paths : Hash(String, String) = {} of String => String
        # Static extends/include/import graph over the loaded templates.
        # Rebuilt whenever templates reload; nil before the first load.
        @template_deps : TemplateDeps?
        # Content hashes of extension-shadowed template files (foo.j2 while
        # foo.html holds the "foo" slot), keyed by source path. Renders can
        # reach these by explicit name through the loader's disk fallback,
        # so run_rerender must treat their edits as template changes even
        # though the snapshot hash itself is unchanged.
        @shadowed_template_hashes : Hash(String, String) = {} of String => String
        # Combined checksum of all templates for the current build — the
        # fallback per-entry template hash when dependency tracking is off.
        @global_templates_hash : String = ""
        # True when per-page template closure hashes drive cache invalidation
        # (config build.template_deps on and the graph is fully static).
        @per_page_template_hash : Bool = false
        # Validated {dir, language} => cascade map captured during the cold
        # build's parse phase — BEFORE draft/expired/future filtering, so
        # incremental passes see the same cascades a cold build applies
        # (a draft section's cascade still reaches its descendants).
        @cascade_map : Hash(Tuple(String, String), Hash(String, Models::ExtraValue))?
        @cache : Cache?
        @config : Models::Config?
        # Digest of the fetched [[data.remote]] payloads for this build,
        # folded into compute_data_hash so a changed payload invalidates
        # cached pages like an edited data/ file. "" when no remote sources
        # are configured (keeps cache keys byte-identical to pre-feature).
        @remote_data_digest : String = ""
        # `[git]` commit metadata keyed by content-relative path, collected
        # ONCE per full build in the Initialize phase (see GitInfo.collect)
        # and read by parse_single_page — including the serve incremental
        # re-parse, which deliberately reuses the last full build's map
        # rather than shelling out to git on every keystroke. Nil when the
        # feature is off or history is unavailable.
        @git_info : Hash(String, Models::GitInfo)? = nil
        # Per-SERVE-SESSION memo of fetched [[data.remote]] payloads. The
        # dev server holds one Builder for the whole session, so this lives
        # exactly as long as `hwaro serve` does; `hwaro build` is one process
        # per build and never populates it, which is why build semantics are
        # untouched.
        #
        # Without it every full rebuild refetched every source synchronously:
        # editing a paragraph offline failed the rebuild, and the default
        # (no `cache`) entry re-hit the network on every unrelated save.
        # Keyed by {entry key, url digest} — not the url itself, which can
        # carry a credential in its query string — so editing either in
        # config.toml misses the memo and refetches, exactly like the disk
        # cache.
        @remote_data_memo : Hash({String, String}, {RemoteData::Result, Time}) = {} of {String, String} => {RemoteData::Result, Time}
        # `[privacy]` localizer for this build (nil when the feature is off).
        # Rebuilt by every Initialize phase; serve's incremental passes reuse
        # the last one, and its disk cache keeps them off the network.
        @privacy : Privacy? = nil
        # Pages whose `[privacy]` rewrite left a reference external because a
        # download failed: their cache entry is dropped, so the next `--cache`
        # build renders them again instead of keeping the external URL.
        # Guarded by @page_derived_mutex.
        @privacy_incomplete : Set(String) = Set(String).new
        # `[csp]`: each HTML file's policy as the Finalize pass emitted it,
        # checked again after `[build] hooks.post` (nil when CSP is off).
        @csp_result : Csp::Result? = nil
        @lifecycle : Lifecycle::Manager
        @context : Lifecycle::BuildContext?
        @profiler : Profiler?
        @crinja_env : Crinja?
        @compiled_templates_cache : Hash(UInt64, Crinja::Template) = {} of UInt64 => Crinja::Template
        # Per-template "can the shortcode processor rewrite this?" decision,
        # keyed by template-source hash. Populated once in load_templates
        # (single-threaded Initialize phase), read-only during render — lets
        # apply_template skip the per-page shortcode scan over template
        # strings that contain no shortcode tokens. A missing key means
        # "unknown": process as before.
        @template_shortcode_scan : Hash(UInt64, Bool) = {} of UInt64 => Bool
        # Crinja-owned regions (raw blocks, macro invocations) masked out of a
        # template source, keyed by that source's hash. Masking is a pure
        # function of the string but used to run once per rendered PAGE; like
        # the scan above it is populated once in load_templates and read-only
        # during render. Also the only place a macro inherited through
        # `{% extends %}` can be seen, since that needs the whole template set.
        @template_literal_masks : Hash(UInt64, {String, Array(String)}) = {} of UInt64 => {String, Array(String)}
        # Which expensive per-page template variables a template's static
        # closure can actually reach. build_template_variables skips building
        # the ones it provably can't (SEO/OG strings, JSON-LD strings, the
        # per-page section-pages array copy — O(section size) per page).
        # Detection is substring-based over the closure's source union, so it
        # only ever over-approximates: any occurrence of the identifier keeps
        # the variable. A template is only gated when its whole closure is
        # statically resolvable AND it cannot contain shortcodes (template
        # shortcodes render with the same vars hash and could read anything).
        #
        # `listing_fanout_*` are the exception: they gate no output at all,
        # only the render phase's auto worker count (see
        # Phases::Render#auto_render_workers). They therefore use TARGETED
        # substrings (`site.pages` / `section.pages`) rather than the
        # deliberately over-broad ones above — over-approximating here costs
        # render parallelism on every site that merely mentions "section".
        record TemplateVarFeatures,
          needs_seo : Bool,
          needs_jsonld : Bool,
          needs_section_pages : Bool,
          listing_fanout_site : Bool,
          listing_fanout_section : Bool
        # Which page fields the site's LISTING templates can actually read.
        # A field folded into the page/section-set fingerprint re-renders every
        # listing whenever that field moves on any page, so `extra` and the
        # content-derived trio (`summary`, `word_count`, `reading_time`) are
        # only fingerprinted when some page-set-dependent template names them.
        # Detection is substring-based over those templates' closure sources,
        # so it only ever over-approximates: naming the field always keeps it.
        record ListingPageFields,
          extra : Bool,
          content_derived : Bool
        # Keyed by entry template NAME (closure semantics are per-name).
        # Populated once in load_templates, read-only during render. Missing
        # key means "unknown": build everything, exactly as before.
        @template_var_features : Hash(String, TemplateVarFeatures) = {} of String => TemplateVarFeatures
        # Tracks shortcode template keys we've already warned about, so a
        # single typo used across many pages emits just one warning line.
        @shortcode_warnings_seen : Set(String)? = nil
        @pages_by_path : Hash(String, Models::Page)?
        @i18n_translations : Content::I18n::TranslationData = Content::I18n::TranslationData.new
        # Per-section cache of Crinja::Value arrays, keyed by
        # {section_name, language} (a tuple, not an interpolated string —
        # these lookups run per page in the render hot path).
        @section_pages_crinja_cache : Hash({String, String?}, Array(Crinja::Value)) = {} of {String, String?} => Array(Crinja::Value)
        # Companion url→index map per section list, populated together with
        # (and invalidated exactly like) @section_pages_crinja_cache. Used
        # for O(1) current-page exclusion in build_template_variables —
        # the previous per-page linear Array#index scan made rendering a
        # flat N-page section O(N²).
        @section_pages_url_index_cache : Hash({String, String?}, Hash(String, Int32)) = {} of {String, String?} => Hash(String, Int32)
        # Per-section cache of Crinja::Value arrays for section assets, keyed by section name
        @section_assets_crinja_cache : Hash(String, Array(Crinja::Value)) = {} of String => Array(Crinja::Value)
        # Track created directories to avoid redundant mkdir_p syscalls
        @created_dirs : Set(String) = Set(String).new
        # Per-page Crinja::Value cache — avoids repeated Page→Crinja::Value conversion
        # across build_global_vars, section page lists, and page_to_crinja_list_value
        @page_crinja_value_cache : Hash(String, Crinja::Value) = {} of String => Crinja::Value
        # Keyed by the series group ({name, language, version}, see
        # Transform#series_group_key), not the bare name.
        @series_crinja_cache : Hash({String, String, String}, Crinja::Value) = {} of {String, String, String} => Crinja::Value
        # Per-section ancestors Crinja::Value cache, keyed by
        # {section_name, language} (pages in the same section+language share ancestors)
        @ancestors_crinja_cache : Hash({String, String?}, Array(Crinja::Value)) = {} of {String, String?} => Array(Crinja::Value)
        # Per-page related_posts Crinja::Value cache (avoids rebuilding the array on each build_template_variables call)
        @related_posts_crinja_cache : Hash(String, Crinja::Value) = {} of String => Crinja::Value
        # Per-page template closure hash memo (page.path → hash). On cached
        # builds the hash is needed twice per page (filter_changed_pages and
        # cache.update) and costs shortcode regex scans over the raw content.
        # Cleared with the runtime caches; incremental builds drop entries
        # for re-parsed pages (their content — hence shortcode usage — may
        # have changed).
        @page_template_hash_memo : Hash(String, String) = {} of String => String
        @page_template_hash_mutex : Mutex = Mutex.new
        # Mutex to protect shared Crinja value caches during parallel rendering.
        # Crystal fibers are single-threaded by default, but this guards against
        # future multi-threaded mode (-Dpreview_mt) and ensures correctness.
        @crinja_cache_mutex : Mutex = Mutex.new(:reentrant)
        # True only while the default (non-streaming) Render phase fan-out runs:
        # prewarm_crinja_caches has filled every Crinja value cache the workers
        # can read, no cache is written until the flag drops, and readers
        # therefore skip @crinja_cache_mutex entirely (concurrent reads of a
        # non-mutated Hash are safe). A frozen-path miss computes its value
        # WITHOUT caching — prewarming makes that a rare one-off, so this can't
        # reintroduce the per-page re-conversion regression that removing the
        # mutex outright caused. Serve/incremental rebuilds, streaming mode
        # (which clears caches mid-run), fast-start deferred renders, and
        # rerenders all run with the flag false, i.e. the locked path.
        @crinja_caches_frozen : Bool = false
        # Mutex to protect created_dirs set during parallel rendering
        # Pages the render loop counted but NO sink could publish (a URL with a
        # traversing segment). Subtracted from `pages_rendered` so the build
        # receipt cannot claim a page that never reached disk. Atomic because
        # the render fan-out increments it from worker fibers.
        # Memo for the listing-template source union (see Phases::Render).
        # Keyed by the templates Hash ITSELF (compared with `same?`) so a
        # template reload recomputes — an `object_id` would let a recycled
        # address serve the previous snapshot's union.
        @listing_source_union_memo : String? = nil
        @listing_source_union_memo_key : Hash(String, String)? = nil
        # Memo for `page_template_scan` (see Phases::Render): what a page's
        # template closure — entry template, the shortcodes its content calls,
        # its output-format templates — reads from other pages. Keyed by the
        # closure roots; reset when the templates Hash itself is replaced
        # (same `same?` rule as the listing-union memo). Read from render
        # worker fibers via record_page_cache_entry, hence the mutex.
        @page_template_scan_memo : Hash(String, Phases::Render::PageTemplateScan) = {} of String => Phases::Render::PageTemplateScan
        @page_template_scan_memo_key : Hash(String, String)? = nil
        @page_template_scan_mutex : Mutex = Mutex.new
        # Shortcode templates a page's content calls, keyed by page path and
        # validated against the raw_content String it was scanned from (a
        # re-parse replaces that String, and a template reload the graph, so
        # the entry self-invalidates).
        @page_shortcodes_memo : Hash(String, {String, TemplateDeps, Set(String)}) = {} of String => {String, TemplateDeps, Set(String)}
        # Relations hashes `filter_changed_pages` compared, by page path, for
        # `record_page_cache_entry` to store. The BeforeRender hooks run in
        # between and fill in page fields (the auto OG image path), so a
        # hash recomputed at record time never matched the next build's
        # filter-time one. Cleared after the render fan-out; guarded by
        # @page_template_hash_mutex.
        @filter_relations_hashes : Hash(String, String) = {} of String => String
        # `[markdown] wikilinks` lookup over the current published page set;
        # rebuilt whenever that set may have changed (refresh_wikilink_index).
        @wikilink_index : Content::Processors::Wikilinks::Index? = nil
        # Ambiguous-wikilink warnings already printed; kept across the index
        # rebuilds of one serve session, cleared by each full build.
        @wikilink_warnings : Content::Processors::Wikilinks::WarnLog = Content::Processors::Wikilinks::WarnLog.new
        # Project-relative path => MD5 of the bytes read (nil: missing, or a
        # transcluded page) for every file an `include_code` / `include_md`
        # call or a `![[note]]` transclusion read. Serve escalates a save
        # of any of them to a full rebuild (Server#effective_strategy). Rebuilt by every full build, so a file
        # nothing includes any more stops escalating.
        @include_sources : Hash(String, String?) = {} of String => String?
        @include_sources_mutex : Mutex = Mutex.new
        # page path => {raw content, wikilink index, include-expanded raw}:
        # `expanded_raw_content`, shared by the render and the per-page scans
        # (fingerprints, serve's template-change selection). Valid while the
        # page's raw string and the index are the same objects; cleared with
        # @include_sources by every full build, the only strategy serve runs
        # after an include source changed. Guarded by @include_sources_mutex.
        @expanded_raw_memo : Hash(String, {String, Content::Processors::Wikilinks::Index?, String}) = {} of String => {String, Content::Processors::Wikilinks::Index?, String}
        @unpublished_pages : Atomic(Int32) = Atomic(Int32).new(0)
        # Pages that actually wrote a file. `process_files_*` returns a delta of
        # this, so every caller (render phase, incremental rebuild, serve
        # re-render, streaming batches) reports the same published-not-processed
        # number instead of each keeping its own bookkeeping.
        @published_pages : Atomic(Int32) = Atomic(Int32).new(0)
        @created_dirs_mutex : Mutex = Mutex.new
        # Explicit render-worker count from `--jobs` (0 = auto/CPU-based).
        # Set from BuildOptions at every build entry point and consumed by
        # process_files_parallel's ParallelConfig. Does not affect output.
        @render_workers : Int32 = 0
        # Unified cache manager for all cache layers
        @cache_manager : CacheManager = CacheManager.new
        # The render phase's site-wide template vars, stashed so the Write
        # phase's 404 page can reuse them. Rebuilding them there re-converted
        # every page/section/taxonomy term to Crinja values and re-hashed
        # every auto-include asset — O(site) work for one page — and silently
        # used cache_busting defaults instead of the build's options.
        @render_global_vars : Hash(String, Crinja::Value)? = nil
        # `[build] write_stats`: tags/classes/ids of every HTML page this
        # Builder wrote, flushed to `hwaro_stats.json`. Nil when the feature
        # is off. Replaced per full build; serve's incremental passes keep
        # adding to it.
        @html_stats : Utils::HtmlStats? = nil
        # Pages stashed by `--fast-start` during the initial build so the
        # dev server can render them in a background fiber after the
        # "ready" signal has been emitted. Nil outside of fast-start mode.
        @deferred_pages : Array(Models::Page)? = nil
        # Deterministic owner (page.path) of every claimed output URL — page
        # URLs and alias destinations. A page that is not the recorded winner
        # for a URL must not write it; under parallel render the colliding
        # file's bytes were whichever worker finished last. Recomputed per
        # full build and per incremental/rerender pass (see
        # compute_output_url_winners). Nil until the first render pass.
        @output_url_winners : Hash(String, String)? = nil
        # Output file key (`PathUtils.output_file_key`) → path of the page
        # that publishes its own HTML there, from the same pass. Generated
        # writers (paginator, taxonomy pages) consult it so they never
        # overwrite an authored page — see `page_output_owner`.
        @page_output_files : Hash(String, String) = {} of String => String
        # Unresolved `@/` internal links collected during the render fan-out
        # when `[links] broken_internal = "error"` (each entry is a formatted
        # "source.md → @/target (reason)" line). Guarded by
        # @broken_links_mutex — render workers append concurrently under
        # -Dpreview_mt. Cleared at every build entry point and aggregated
        # into one classified error by raise_on_broken_internal_links!.
        @broken_internal_links : Array(String) = [] of String
        @broken_links_mutex : Mutex = Mutex.new
        # Fragment links (`@/x.md#id`, same-page `#id`) found in rendered page
        # content, collected only when `[links] broken_anchors` is not
        # "ignore": {source path, link as written, target page, fragment}.
        # Same mutex and lifetime as @broken_internal_links; checked against
        # the target's output file by check_broken_anchors.
        @anchor_links : Array({String, String, Models::Page, String}) = [] of {String, String, Models::Page, String}
        # Output files this build claims that no content source backs — the
        # taxonomy index/term pages, their pagination pages and their feeds.
        # A page's own output is recorded in its cache entry; these have no
        # entry to record them, so the Finalize phase persists this set and
        # deletes what the PREVIOUS build claimed and this one no longer does
        # (a term whose last post was deleted). Only a claim recorded here can
        # ever be deleted, so a generator that reports nothing simply keeps
        # today's behaviour instead of losing files. Reset by the Initialize
        # phase; guarded because taxonomy rendering fans out.
        @generated_output_claims : Set(String) = Set(String).new
        # What the builder had claimed when the current build reset the set:
        # the previous build's claims plus everything a serve session's
        # incremental passes claimed since. Without `--cache` there is no
        # persisted list to diff against, and this in-memory one is what lets
        # a `hwaro serve` full rebuild drop the outputs it no longer
        # publishes (a superseded `main.<hash>.css`, the `amp/` tree after
        # `[amp]` is switched off). Empty on a process's first build.
        @previous_generated_claims : Set(String) = Set(String).new
        # The claims above that a GENERATOR made — every claimer but the
        # static copy (404.html, feeds, sitemap, robots, llms, the search
        # index, taxonomy pages, raw content files, bundles). On a cold build
        # each of them is written after `static/` is copied, so a static file
        # at one of these paths loses; the serve static lane needs to know
        # when an edit lands on one (see `copy_changed_static`). Reset with
        # the claims; guarded by @generated_claims_mutex.
        @generator_output_claims : Set(String) = Set(String).new
        # True while @generated_output_claims is the running full build's own
        # set (reset by the Initialize phase); false once an incremental serve
        # pass starts, which re-claims nothing — so the set then still names
        # outputs that pass is pruning. See `prune_unclaimed_outputs`.
        @generated_claims_current : Bool = false
        # Every page output the site of the PREVIOUS build (as the serve
        # session's incremental passes left it) claimed, captured by `run`
        # before it drops that site. A full serve rebuild — any config or
        # data edit, or a file added alongside a content edit — renders only
        # the new site and never looked back, so a page it moved (`slug`,
        # `path`, a permalink rule), drafted or turned `render = false` kept
        # its old file. Empty on a process's first build.
        @previous_page_outputs : Set(String) = Set(String).new
        # Output files the pages an incremental serve pass re-parsed occupied
        # BEFORE the re-parse, until that pass has pruned what they left. The
        # re-parse moves the page model in place, so a pass that raises in
        # between (a date-token permalink error) used to leave the old file
        # behind for good: the recovering full build computes
        # `@previous_page_outputs` from the MOVED model. Drained by the next
        # pass that gets as far as pruning, or by the Finalize phase.
        @unsettled_page_outputs : Set(String) = Set(String).new
        # True from the moment a build starts replacing the site until its
        # Finalize prune has consumed the two baselines above. A build that
        # fails in between (a broken template) leaves them describing its
        # half-built state, so the next one carries them forward instead of
        # recomputing them — otherwise a source deleted during the broken
        # stretch is forgotten and its output is served for the rest of the
        # session.
        @prune_baselines_pending : Bool = false
        @carry_prune_baselines : Bool = false
        @generated_claims_mutex : Mutex = Mutex.new
        # Output files the static copy actually (re)wrote this build, in the
        # canonical absolute form `get_output_path` produces. `static/` is
        # copied in the Initialize phase and the render phase runs after it,
        # so on a cold build a page always wins a shared path
        # (`static/about/index.html` vs `content/about.md`). On a warm
        # `--cache` build the page is a cache hit and never re-renders, so the
        # static copy's bytes REPLACED the page — `public/about/index.html`
        # served the static file until an unrelated edit. Pages whose output
        # this set names are forced back through the render (see
        # filter_changed_pages), which restores the cold build's outcome.
        @static_copied_outputs : Set(String) = Set(String).new
        @static_copied_mutex : Mutex = Mutex.new
        # Wall clock at the moment this build started writing into the output
        # directory. The Finalize prune refuses to delete anything modified
        # at or after it: whatever this build WROTE is live by definition,
        # whether or not any bookkeeping claims it. That is what keeps a
        # shadowed generator output safe — `static/robots.txt` and the
        # generated `robots.txt` are the same file, so dropping the static
        # claim when the source is deleted would otherwise take the generated
        # one with it.
        #
        # nil until `mark_build_output_epoch` stamps it, which the Initialize
        # phase does before the first write. Unstamped means "no build has
        # written here", and the guard then protects nothing — a caller that
        # drives the Finalize phase without a build (unit specs) gets exactly
        # the pruning contract it asks for.
        @build_output_epoch : Time? = nil
        # The output directory when this build kept the previous build's tree
        # (`--cache`, serve), nil when it started from an empty one. Only a
        # kept tree can hold a leftover of the other kind where this build
        # writes (see `mkdir_output`).
        @kept_output_dir : String? = nil
        # Files a page wrote BESIDES its own output: its `aliases` redirect
        # stubs and, for a section, its `/page/N/` pagination pages. Both are
        # produced by the render pass, so a warm `--cache` build that skips a
        # page never re-derives them — they go into the page's cache entry
        # (`derived_paths`) instead, which is what lets a removed page take its
        # stubs with it and a section that lost a page drop the pagination page
        # it no longer fills. Keyed by page.path, filled during render_page and
        # drained by record_page_cache_entry a few lines later in the same
        # worker fiber.
        @page_derived_outputs : Hash(String, Array(String)) = {} of String => Array(String)
        @page_derived_mutex : Mutex = Mutex.new
        # The derived files (see above) each page's LAST render wrote, and
        # those the running pass has recorded so far. The cache entry is the
        # only other record, and it is pruned only by a `--cache` build's
        # Finalize — so a `hwaro serve` session kept serving an alias stub
        # after the alias was removed (or its page deleted or drafted) and a
        # `/page/N/` a shrinking section no longer fills. Diffed by
        # `sweep_stale_derived_outputs` once a render pass has finished.
        # Guarded by @page_derived_mutex.
        @rendered_derived_outputs : Hash(String, Array(String)) = {} of String => Array(String)
        @derived_outputs_this_pass : Hash(String, Array(String)) = {} of String => Array(String)
        # Taxonomy index/term/pagination/feed files the PREVIOUS taxonomy
        # generation wrote, and the set the running one is collecting (nil
        # outside a pass). The Finalize prune covers these only on a `--cache`
        # build, and only on the full-build path — a `hwaro serve` session
        # without `--cache`, and every incremental rebuild with it, left a
        # term whose last post was deleted (or re-tagged) served until
        # restart. The serve builder lives for the whole session, so the
        # previous pass is right here in memory. Guarded by
        # @generated_claims_mutex (taxonomy rendering fans out).
        @last_taxonomy_outputs : Set(String)? = nil
        # Feed files the last feed generation published (full build or serve
        # pass). A section's `generate_feeds` lives in front matter, so an
        # incremental serve edit can stop a section feed — and incremental
        # passes run no claims diff. See `track_feed_outputs`. Guarded by
        # @generated_claims_mutex.
        @last_feed_outputs : Set(String)? = nil
        @taxonomy_pass_outputs : Set(String)? = nil
        # Content-relative directories that host a bundle index (`index.md` /
        # `_index.md`, any language) as READ — before draft/future/expiry
        # filtering. A directory here whose index pages all failed the filter
        # is a withheld bundle: its files must not publish through the raw
        # lane either (see Phases::Write#withheld_content_file?).
        @content_index_dirs : Set(String) = Set(String).new

        def initialize
          @lifecycle = Lifecycle::Manager.new
          setup_cache_manager
        end

        # Record an output file this build produced that no cache entry
        # covers. Public: the taxonomy generator is a module that reaches the
        # builder through its `builder:` argument.
        #
        # `static_copy` marks the Initialize phase's copy of `static/`: it is
        # a claim like any other, but not a generator's (see
        # `@generator_output_claims`).
        def claim_generated_output(path : String, static_copy : Bool = false) : Nil
          @generated_claims_mutex.synchronize do
            @generated_output_claims << path
            @generator_output_claims << path unless static_copy
            @taxonomy_pass_outputs.try(&.<<(path))
          end
        end

        # Everything claimed since the last reset.
        def generated_output_claims : Set(String)
          @generated_claims_mutex.synchronize { @generated_output_claims.dup }
        end

        def reset_generated_output_claims : Nil
          @generated_claims_mutex.synchronize do
            @previous_generated_claims = @carry_prune_baselines ? @previous_generated_claims | @generated_output_claims : @generated_output_claims
            @generated_output_claims = Set(String).new
            @generator_output_claims = Set(String).new
          end
          @generated_claims_current = true
        end

        # Record an output file the static copy just wrote over (see
        # `@static_copied_outputs`). Public because the serve watcher's
        # static-only lane (`copy_changed_static`) copies through the builder
        # too and must record what it wrote for the same reason. `path` must
        # already be canonical — see `static_copied_output?`.
        def note_static_copy(path : String) : Nil
          @static_copied_mutex.synchronize { @static_copied_outputs << path }
        end

        # Did the static copy write anything at all this build? The gate in
        # filter_changed_pages resolves paths against the working directory,
        # and this lets it skip that work entirely on the common warm build
        # where no static file changed.
        def static_copies_recorded? : Bool
          @static_copied_mutex.synchronize { !@static_copied_outputs.empty? }
        end

        # `path` may arrive in any spelling — `get_output_path` hands back the
        # canonical absolute form while alias/pagination paths are built by
        # joining the output directory — so it is resolved against `cwd` (the
        # caller's, resolved once) before the lookup.
        def static_copied_output?(path : String, cwd : String) : Bool
          @static_copied_mutex.synchronize do
            return false if @static_copied_outputs.empty?
            @static_copied_outputs.includes?(File.expand_path(path, cwd))
          end
        end

        def reset_static_copied_outputs : Nil
          @static_copied_mutex.synchronize { @static_copied_outputs.clear }
        end

        # Stamp the start of this build's output writing (see
        # `@build_output_epoch`).
        def mark_build_output_epoch : Nil
          @build_output_epoch = Time.utc
        end

        # True when `path` was (re)written by this build.
        #
        # Exact on every filesystem with sub-second mtimes (APFS, ext4, btrfs,
        # NTFS, xfs): a previous build's file is stamped strictly before this
        # build's epoch, and everything this build writes strictly after. The
        # comparison carries NO slack on purpose — a slack wide enough to
        # cover a coarse filesystem is also wide enough to protect the
        # previous build's output, which would disable pruning outright for
        # any two builds run seconds apart.
        #
        # On a filesystem that truncates mtimes to whole seconds a shadowed
        # generator file written in the epoch's own second can read as older
        # and be pruned. That is self-healing: the path leaves the claim list
        # with it, and the next build's generator finds the file missing and
        # writes it again.
        #
        # Widening the comparison (a slack, or truncating the epoch to its own
        # second) trades that for a PERMANENT failure instead. A path the
        # prune skips is not re-claimed by the build that skipped it, so it
        # never appears in a later build's stale list either — the leftover
        # stays published forever. Two builds run seconds apart are ordinary,
        # so the widened form also protects the PREVIOUS build's output as a
        # matter of course: both widenings were measured against
        # cache_stale_outputs_spec and disable pruning outright (12+ of its 22
        # examples). Erring toward pruning is the recoverable direction.
        #
        # The stamped copies (static files, bundle assets — `File.utime` with
        # the SOURCE mtime) deliberately read as old, and they are exactly the
        # ones a live claim already protects.
        def written_this_build?(path : String) : Bool
          epoch = @build_output_epoch
          return false unless epoch
          info = File.info?(path)
          return false unless info
          info.modification_time >= epoch
        end

        # Record an alias stub / pagination page / localized `[privacy]`
        # file `page` just wrote.
        def record_page_derived_output(page_path : String, output_path : String) : Nil
          @page_derived_mutex.synchronize do
            list = @page_derived_outputs[page_path] ||= [] of String
            list << output_path unless list.includes?(output_path)
          end
        end

        # `[privacy]`: the local URL for one external URL (the PWA precache
        # list), or nil to keep it external.
        def privacy_url(url : String) : String?
          return unless localized = @privacy.try(&.localize(url))
          localized.files.each { |path| claim_generated_output(path) }
          localized.url
        end

        # `[privacy]`: point `html`'s external assets at local copies. The
        # files they now load are claimed, and recorded against `owner` (a
        # page path) so a `--cache` hit, which skips the render, keeps them.
        # Public: the taxonomy generator writes through it too.
        def privacy_rewrite(html : String, owner : String? = nil) : String
          return html unless privacy = @privacy
          html, files, incomplete = privacy.rewrite_html(html)
          files.each do |path|
            claim_generated_output(path)
            record_page_derived_output(owner, path) if owner
          end
          @page_derived_mutex.synchronize { @privacy_incomplete << owner } if incomplete && owner
          html
        end

        # Start this page's list over — called at the top of every render so a
        # `serve` session's repeated rebuilds don't accumulate.
        def clear_page_derived_outputs(page_path : String) : Nil
          @page_derived_mutex.synchronize { @page_derived_outputs.delete(page_path) }
        end

        # Take (and forget) what this page derived, remembering it as what the
        # page's render in this pass wrote (see `@derived_outputs_this_pass`).
        def take_page_derived_outputs(page_path : String) : Array(String)
          @page_derived_mutex.synchronize do
            derived = @page_derived_outputs.delete(page_path) || [] of String
            @derived_outputs_this_pass[page_path] = derived
            derived
          end
        end

        # Access cache manager for external inspection
        def cache_manager : CacheManager
          @cache_manager
        end

        # Profiler to thread into per-page render loops, or nil when
        # profiling is off. The record_* methods already no-op when
        # disabled, but callers test the reference before taking
        # timestamps — passing nil skips two Time.instant calls and a
        # redundant determine_template per rendered page.
        private def active_profiler : Profiler?
          @profiler.try { |p| p.enabled? ? p : nil }
        end

        # Access build context for external inspection (e.g. emitting JSON
        # output after a build). Returns nil before `run` has been invoked.
        def context : Lifecycle::BuildContext?
          @context
        end

        # The most recently loaded site config (nil before the first build).
        # The serve watcher reads it to diff restart-only [serve] settings
        # after a config-triggered rebuild.
        def config : Models::Config?
          @config
        end

        # The most recently built site (nil before the first build). The dev
        # server's lazy OG handler reads it to match a requested image path
        # back to the page that owns it.
        def site : Models::Site?
          @site
        end

        # Register all cache layers with the unified manager
        private def setup_cache_manager
          @cache_manager.register("compiled_templates", "Compiled Crinja template ASTs", runtime: true) do
            @compiled_templates_cache.clear
          end
          @cache_manager.register("page_crinja_value", "Page→Crinja::Value conversions", runtime: true) do
            @page_crinja_value_cache.clear
          end
          @cache_manager.register("section_pages_crinja", "Section page lists as Crinja values", runtime: true) do
            @section_pages_crinja_cache.clear
            @section_pages_url_index_cache.clear
          end
          @cache_manager.register("section_assets_crinja", "Section asset lists as Crinja values", runtime: true) do
            @section_assets_crinja_cache.clear
          end
          @cache_manager.register("series_crinja", "Series page lists as Crinja values", runtime: true) do
            @series_crinja_cache.clear
          end
          @cache_manager.register("ancestors_crinja", "Ancestor pages as Crinja values", runtime: true) do
            @ancestors_crinja_cache.clear
          end
          @cache_manager.register("related_posts_crinja", "Related posts as Crinja values", runtime: true) do
            @related_posts_crinja_cache.clear
          end
          @cache_manager.register("page_template_hash", "Per-page template closure hashes", runtime: true) do
            @page_template_hash_mutex.synchronize { @page_template_hash_memo.clear }
          end
          @cache_manager.register("build_cache", "Persistent file-change tracking (.hwaro_cache.json)", runtime: false) do
            @cache.try(&.clear)
          end
        end

        # Register a Hookable module
        def register(hookable : Lifecycle::Hookable)
          @lifecycle.register(hookable)
          self
        end

        # Full build. The incoming struct is stored on the BuildContext
        # verbatim, so every field (`full`, `serve_mode`, …) reaches the
        # phases and hooks that branch on them (`--full` cache clearing,
        # `[og.image] lazy_generate` under serve).
        #
        # Returns false when the build failed without raising (pre-hook
        # failure or a phase abort) — the serve watcher branches on this to
        # surface the failure instead of live-reloading onto a broken site.
        def run(options : Config::Options::BuildOptions) : Bool
          @render_workers = options.workers
          # Load config once and reuse throughout the build.
          # `Models::Config.load` raises `HwaroError(HWARO_E_CONFIG)` directly
          # for missing files and TOML parse failures, so callers (and
          # `--json` consumers) can branch on HWARO_E_CONFIG without the
          # build pipeline rewrapping the exception.
          config = Models::Config.load(env: options.env)
          @config = config
          # `[build]` supplies output_dir/drafts/parallel/cache for anything the
          # command line left at its default. Applied before the BuildContext is
          # built so every phase (and the output guard) sees the same values.
          options.apply_build_config!(config.build)
          @html_stats = config.build.write_stats ? Utils::HtmlStats.new : nil
          pre_hooks = config.build.hooks.pre
          post_hooks = config.build.hooks.post

          # Run pre-build hooks
          unless pre_hooks.empty?
            unless Utils::CommandRunner.run_pre_hooks(pre_hooks)
              # Classified, not `return false`. Returning false made the CLI
              # synthesize HWARO_E_INTERNAL / exit 70 — the code reserved for
              # hwaro's own bugs — for a user command listed in config.toml
              # exiting non-zero, so CI that alerts on internal faults fired
              # on `npm run build` failing. `hwaro serve` treats a raise and a
              # false the same way (see Server#apply_changeset), so the dev
              # loop is unaffected.
              raise Hwaro::HwaroError.new(
                code: Hwaro::Errors::HWARO_E_CONFIG,
                message: "Build aborted: a [build] hooks.pre command failed (see the command output above).",
                hint: "Fix the failing command, or remove it from hooks.pre in config.toml.",
              )
            end
          end

          # The build runs quietly; its story is told by the closing receipt
          # (and, under -Dpreview_mt TTY, the live status line in Phase 3).
          start_time = Time.instant

          # Initialize profiler
          profiler = Profiler.new(enabled: options.profile)
          @profiler = profiler

          if options.streaming?
            Logger.info "  Streaming mode enabled (batch size: #{options.batch_size})"
          end

          ctx = Lifecycle::BuildContext.new(options)
          ctx.stats.start_time = Time.instant
          ctx.profiler = profiler if profiler.enabled?
          ctx.builder = self
          @context = ctx

          # Reset internal caches (preserve @config loaded above)
          @carry_prune_baselines = @prune_baselines_pending
          @prune_baselines_pending = true
          current_outputs = @site ? owned_output_paths(options.output_dir) : Set(String).new
          @previous_page_outputs = @carry_prune_baselines ? @previous_page_outputs | current_outputs : current_outputs
          @site = nil
          @templates = nil
          @cache_manager.clear_runtime
          @created_dirs.clear
          clear_broken_internal_links
          # The load_data() memo is keyed by ms-mtime, which a rewrite inside
          # one filesystem timestamp tick does not move; a build must read
          # the data files as they are now, not as a previous build saw them.
          Content::Processors::TemplateEngine.clear_load_data_cache
          # Same for the SRI digests (keyed on mtime + size, so this is
          # belt-and-braces) and the record `hooks.post` is checked against.
          Utils::SriCache.clear
          # Include sources and the expanded-content memo are re-learned by
          # this build's render.
          @include_sources_mutex.synchronize do
            @include_sources = {} of String => String?
            @expanded_raw_memo.clear
          end
          # Same lifetime for the once-per-BUILD shortcode warnings (missing
          # template, unclosed block): a `serve` session that never cleared them
          # reported each name only for the first rebuild it appeared in.
          @shortcode_warnings_seen = nil

          # Execute build phases through lifecycle. The live status region
          # animates the current phase on a TTY; `ensure` guarantees the
          # spinner is torn down (and its line cleared) on every exit path
          # before the receipt prints.
          Logger.status_start(verbose: options.verbose)
          begin
            result = execute_phases(ctx, profiler)
          ensure
            Logger.status_finish
          end

          ctx.stats.end_time = Time.instant

          if result == Lifecycle::HookResult::Abort
            # Phase bodies convert non-classified exceptions into Abort (see
            # Lifecycle::Manager); returning false lets callers that can't
            # rely on an exception — the serve watcher, `hwaro build`'s exit
            # code — still observe the failure.
            Logger.error "Build failed!"
            return false
          end

          elapsed = Time.instant - start_time
          raw_msg = ctx.stats.raw_files_processed > 0 ? " + #{ctx.stats.raw_files_processed} raw files" : ""
          # "content pages" rather than just "pages" — taxonomy/archive/section
          # index files are also written to disk, so a bare "N pages" count
          # misleads users who diff this number against `find public -name '*.html'`.
          emit_build_receipt(ctx, raw_msg, elapsed.total_milliseconds, profiler)
          # Only warn about an empty site when nothing was built at all. Under
          # `--cache`, unchanged pages are skipped (counted as `cache_hits`)
          # rather than re-rendered, so `pages_rendered` is 0 on a no-op rebuild
          # even though the site is full — guarding on `cache_hits == 0` keeps
          # the hint from misfiring on every cached rebuild.
          if ctx.stats.pages_rendered == 0 && ctx.stats.cache_hits == 0 && ctx.stats.raw_files_processed == 0
            Logger.info "No content found. Add Markdown files under content/ before deploying, or run `hwaro new <path>.md` to scaffold one."
          end

          # Human-readable reports (--profile, --debug) go to stderr under
          # --json: stdout must carry exactly one JSON document, and these
          # tables printed ahead of the build envelope made it unparseable.
          # Through Logger's guarded streams: on a closed stdout (a serve whose
          # reader went away) a raw STDOUT write failed the rebuild here, after
          # the pages were written but before the post-build hooks.
          report_io = CLI::Runner.json_mode? ? Logger.err_io : Logger.io

          # Print profiling report if enabled
          profiler.report(report_io)
          profiler.template_report(report_io)
          profiler.markdown_report(report_io)
          profiler.asset_report(report_io)
          profiler.hook_report(report_io)

          # Print cache stats
          report_cache_stats(options.verbose)

          # Run post-build hooks
          unless post_hooks.empty?
            # Files already off their printed value were changed by the build
            # itself (Write's minify, Finalize's prune), not by the hooks.
            stale_before = Utils::SriCache.stale.to_set
            unless Utils::CommandRunner.run_post_hooks(post_hooks)
              Logger.warn "Post-build hooks failed, but build was successful."
            end
            warn_integrity_changed_by_post_hooks(stale_before)
            warn_csp_changed_by_post_hooks(config)
          end

          if options.debug
            if debug_site = @site
              Utils::DebugPrinter.print(debug_site, report_io)
            end
          end

          true
        end

        # The pages carry `integrity` values hashed during Render; a post hook
        # that rewrote one of those files (a minifier over public/) makes the
        # browser block it. Nothing re-renders after the hooks, so say so.
        private def warn_integrity_changed_by_post_hooks(stale_before : Set(String))
          Utils::SriCache.stale.each do |path|
            next if stale_before.includes?(path)
            Logger.warn "[build] hooks.post changed #{path} after its integrity was printed into pages; browsers will block it. Rewrite it in hooks.pre (into static/) instead."
          end
        end

        # Same for `[csp]`: the policies hash the inline bytes Finalize saw.
        private def warn_csp_changed_by_post_hooks(config : Models::Config)
          return unless result = @csp_result
          Csp.changed_pages(config.csp, result).each do |path|
            Logger.warn "[build] hooks.post changed inline scripts or styles in #{path} after its Content-Security-Policy was computed; browsers will block them. Make the change in hooks.pre or a template instead."
          end
        end

        # Emit the end-of-build cache statistics at the requested verbosity.
        private def report_cache_stats(verbose : Bool)
          verbose ? @cache_manager.report_verbose : @cache_manager.report
        end

        # Selectively invalidate Crinja caches for changed pages and affected sections.
        # Fixes stale cache entries during incremental builds.
        private def invalidate_caches_for_pages(
          changed_pages : Array(Models::Page),
          affected_sections : Set(String),
        )
          @crinja_cache_mutex.synchronize do
            changed_pages.each do |page|
              @page_crinja_value_cache.delete(page.path)
              @related_posts_crinja_cache.delete(page.path)

              if series_name = page.series
                @series_crinja_cache.reject! { |key, _| key[0] == series_name }
              end

              # Neighbors' cached values reference this page
              page.lower.try { |l| @page_crinja_value_cache.delete(l.path) }
              page.higher.try { |h| @page_crinja_value_cache.delete(h.path) }
            end

            affected_sections.each do |section_name|
              # Keyed by {section, language} (see build_template_variables), so
              # drop every language's entry for the section, like section_pages.
              @ancestors_crinja_cache.reject! { |k, _| k[0] == section_name }
              @section_pages_crinja_cache.reject! { |k, _| k[0] == section_name }
              @section_pages_url_index_cache.reject! { |k, _| k[0] == section_name }
              @section_assets_crinja_cache.delete(section_name)
            end
          end
        end

        # Emit the calm closing receipt: an aligned per-phase summary plus the
        # one ember "built" outcome line. Rows are skipped when their value is
        # empty, so cached/no-op rebuilds stay terse. Falls back to plain
        # "label: value" lines (no color, no rule) when color is off. Each row
        # carries its phase timing as a TTY-only dim detail so slow phases are
        # visible at a glance without `--profile`.
        private def emit_build_receipt(ctx : Lifecycle::BuildContext, raw_msg : String, elapsed_ms : Float64, profiler : Profiler)
          stats = ctx.stats
          receipt = Logger::Receipt.new("build")
          receipt.row("read", stats.pages_read > 0 ? "#{stats.pages_read} content files" : "",
            detail: phase_detail(profiler, "ReadContent"))
          parsed = stats.pages_read - stats.pages_skipped
          receipt.row("parse", parsed > 0 ? "#{parsed} pages" : "",
            emphasis: stats.pages_skipped > 0 ? "#{stats.pages_skipped} skipped" : nil,
            detail: phase_detail(profiler, "ParseContent"))
          render_val =
            if stats.cache_hits > 0
              "#{stats.pages_rendered} pages · #{stats.cache_hits} cached"
            else
              "#{stats.pages_rendered} pages"
            end
          receipt.row("render", render_val, detail: phase_detail(profiler, "Render"))
          receipt.row("write", stats.raw_files_processed > 0 ? "#{stats.raw_files_processed} raw files" : "",
            detail: phase_detail(profiler, "Write"))
          if stats.pages_unpublished > 0
            receipt.row("skipped", "#{stats.pages_unpublished} not published", emphasis: "see warnings above")
          end
          receipt.outcome("built", "#{stats.pages_rendered} content pages#{raw_msg}", :result, elapsed_ms)
          receipt.emit
        end

        # A receipt row's dim timing note. Sub-millisecond phases return `nil`
        # so trivial builds don't sprout four "0ms" notes.
        private def phase_detail(profiler : Profiler, phase : String) : String?
          ms = profiler.phase_ms(phase)
          ms && ms >= 1.0 ? Logger.dur(ms) : nil
        end

        # Execute all build phases with lifecycle hooks
        private def execute_phases(
          ctx : Lifecycle::BuildContext,
          profiler : Profiler,
        ) : Lifecycle::HookResult
          # Phase: Initialize
          result = execute_initialize_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: ReadContent
          result = execute_read_content_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: ParseContent
          result = execute_parse_content_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Transform
          result = execute_transform_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Render
          result = execute_render_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Generate
          result = execute_generate_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          if ctx.options.streaming?
            ctx.all_pages.each(&.raw_content=(""))
            GC.collect
          end

          # Phase: Write
          result = execute_write_phase(ctx, profiler)
          return result if result != Lifecycle::HookResult::Continue

          # Phase: Finalize
          execute_finalize_phase(ctx, profiler)
        end
      end
    end
  end
end
