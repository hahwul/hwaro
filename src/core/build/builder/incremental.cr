# Builder — serve-mode incremental strategies (re-parse, re-render, deferred fast-start pages).
#
# Reopens `Core::Build::Builder`; builder.cr keeps the require order, the
# phase includes, every ivar and the cold-build `run`. Parts only reopen the
# class: no requires, no load-time statements
# (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Core
    module Build
      class Builder
        # Drop unresolved-link records from the previous pass so a fixed
        # link doesn't keep failing (and a new one is attributed to the
        # right build). Called at every build entry point.
        private def clear_broken_internal_links
          @broken_links_mutex.synchronize do
            @broken_internal_links.clear
            @anchor_links.clear
          end
        end

        # Record every fragment link in `html` (content HTML BEFORE `@/`
        # resolution, so the target page is still known by its source path)
        # for check_broken_anchors. An `@/` link whose page doesn't exist is
        # skipped: [links] broken_internal already reports it.
        private def collect_anchor_links(page : Models::Page, html : String, pages_by_path : Hash(String, Models::Page)) : Nil
          found = [] of {String, String, Models::Page, String}
          html.scan(Content::Processors::InternalLinkResolver::FRAGMENT_LINK_REGEX) do |m|
            fragment = m[2]
            next if fragment.empty?
            if link_path = m[1]?
              next unless target = Content::Processors::InternalLinkResolver.page_for(pages_by_path, link_path.lchop("@/").partition('?')[0])
            else
              target = page
            end
            found << {page.path, "#{link_path}##{fragment}", target, fragment}
          end
          @broken_links_mutex.synchronize { @anchor_links.concat(found) } unless found.empty?
        end

        # Check the collected fragment links against the `id`/`name`
        # attributes in each target's output file ON DISK, so a target the
        # pass didn't re-render (`--cache`, serve partial rebuilds) is read as
        # last written instead of producing a false positive. A target with no
        # output file (render: false, a refused URL) is skipped — unless it is
        # a fast-start deferred page not written yet: that link goes back in
        # the queue for render_deferred to check. Consumes the rest, so the
        # deferred pass doesn't re-report the priority pass's links. "warn"
        # logs each; "error" raises one aggregated HWARO_E_CONTENT error.
        private def check_broken_anchors(output_dir : String) : Nil
          links = @broken_links_mutex.synchronize { @anchor_links.dup.tap { @anchor_links.clear } }
          return if links.empty?
          return unless site = @site

          ids_by_file = {} of String => Set(String)?
          broken = [] of String
          pending = [] of {String, String, Models::Page, String}
          deferred = @deferred_pages
          links.each do |entry|
            source, link, target, fragment = entry
            next unless file = get_output_path(target, output_dir)
            ids = ids_by_file.put_if_absent(file) do
              File.file?(file) ? Content::Processors::InternalLinkResolver.anchor_ids(File.read(file)) : nil
            end
            unless ids
              pending << entry if deferred && deferred.includes?(target)
              next
            end
            next if Content::Processors::InternalLinkResolver.anchor_exists?(fragment, ids)
            broken << "#{source} → #{link} → missing id \"#{URI.decode(HTML.unescape(fragment))}\""
          end
          @broken_links_mutex.synchronize { @anchor_links.concat(pending) } unless pending.empty?
          broken.sort!.uniq!
          return if broken.empty?

          if site.config.links.broken_anchors == "error"
            label = broken.size == 1 ? "1 broken anchor" : "#{broken.size} broken anchors"
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONTENT,
              message: "#{label}:\n  #{broken.join("\n  ")}",
              hint: "Fix the #fragment links above, or set [links] broken_anchors = \"warn\" to demote them to warnings.",
            )
          end
          broken.each { |entry| Logger.warn "Broken anchor: #{entry}" }
        end

        # Fail the build with ONE aggregated error listing every unresolved
        # `@/` internal link collected during the render fan-out. Only
        # populated when `[links] broken_internal = "error"` — the default
        # "warn" mode never appends, making this a no-op there. Raising
        # HwaroError(HWARO_E_CONTENT) maps to exit code 5 for CI; under
        # `serve` the watcher rescue surfaces it in the error overlay.
        private def raise_on_broken_internal_links!(output_dir : String)
          # Dedupe: the same broken @/target repeated within one page (or a
          # page rendered twice in a pass) must produce one line, not N.
          entries = @broken_links_mutex.synchronize { @broken_internal_links.sort.uniq! }
          unless entries.empty?
            label = entries.size == 1 ? "1 broken internal link" : "#{entries.size} broken internal links"
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_CONTENT,
              message: "#{label}:\n  #{entries.join("\n  ")}",
              hint: "Fix the @/ links above, or set [links] broken_internal = \"warn\" to demote them to warnings.",
            )
          end
          check_broken_anchors(output_dir)
        end

        # Incremental build: only re-parse and re-render pages whose source
        # files have been modified.  Falls back to a full build when the
        # necessary state from a previous build is not available.
        #
        # Optimizations over a full build:
        # - Only re-parses changed files (not all pages)
        # - Diff-based taxonomy update (not full rebuild)
        # - Re-links navigation only for affected sections
        # - Recomputes series/related posts only for affected pages
        # - Selectively invalidates Crinja caches
        def run_incremental(changed_content_files : Array(String), options : Config::Options::BuildOptions) : Bool
          @render_workers = options.workers
          config = @config
          site = @site
          templates = @templates

          # First build hasn't happened yet – fall back to full build
          unless config && site && templates
            return run(options)
          end

          Logger.info "Incremental build for #{changed_content_files.size} changed file(s)..." if options.verbose
          start_time = Time.instant
          begin_serve_pass
          clear_broken_internal_links

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose

          # --- 1. Identify changed pages and snapshot their state before re-parse ---
          # Digest every page-set projection the templates read, BEFORE the
          # re-parse, so the fan-out below can tell which of them this edit
          # actually moved. See listing_fanout_pages.
          listing_sets = snapshot_listing_sets(site, templates)
          backlink_digests = snapshot_backlinks(site, templates)

          # Build O(1) lookup map for changed file matching
          pages_map = @pages_by_path || build_pages_by_path(site)

          reparsed = reparse_changed_pages(changed_content_files, site, config, output_dir, pages_map)
          return run(options) unless reparsed
          changed_pages = reparsed.changed_pages
          affected_sections = reparsed.affected_sections
          old_taxonomies_snapshot = reparsed.old_taxonomies_snapshot
          old_series_names = reparsed.old_series_names
          old_output_paths = reparsed.old_output_paths

          if changed_pages.empty?
            Logger.info "  No matching pages found – skipping."
            return true
          end

          # Re-claim output URLs: the edit may have introduced or resolved a
          # slug/alias collision, and a stale winner map would keep
          # suppressing (or racing) writes for the rest of the serve session.
          @output_url_winners = compute_output_url_winners((site.pages + site.sections).as(Array(Models::Page)))

          # --- 2. Incrementally update relationships ---
          # Identify pages that should be excluded (draft/expired/future)
          # BEFORE the taxonomy update, so their re-parsed terms don't get
          # re-added to site.taxonomies — pages rendered in this same pass
          # would otherwise still show the drafted page in tag clouds and
          # term counts until the next full build.
          excluded_pages = apply_publication_exclusions!(changed_pages, options)
          excluded_paths = excluded_pages.map(&.path).to_set

          # Date-token permalink errors deferred by the lenient parse (see
          # ParseContent#calculate_page_url): now that cascades and the
          # exclusion pass ran, a surviving renderable page must fail the
          # rebuild — same contract as the full parse phase. The serve
          # watcher surfaces this via the overlay and escalates the next
          # rebuild through @rebuild_failed.
          raise_on_permalink_errors!(changed_pages)

          # Re-render <!-- more --> summaries for the re-parsed pages with the
          # body pipeline (parse_single_page reset summary_html to nil); the
          # listing pages re-rendered below read it. Runs AFTER the exclusion
          # pass so a page just flipped to draft can't feed its summary's
          # broken @/ links into the strict-mode accumulator (the full build
          # renders summaries post-filter too).
          # The excluded pages leave site.pages only at
          # drop_excluded_and_orphaned_outputs below; keep them out of the
          # index now, or the summaries and renders here still link to them.
          refresh_wikilink_index((site.pages + site.sections).reject { |p| excluded_paths.includes?(p.path) }, site)
          render_page_summaries(changed_pages, site, templates, highlight,
            link_targets: (site.pages + site.sections).as(Array(Models::Page)))

          # Run taxonomy update on ALL re-parsed pages (including the excluded
          # ones — their OLD entries must be removed; excluded_paths keeps
          # their new terms from being re-added).
          update_taxonomies_incremental(site, changed_pages + excluded_pages, old_taxonomies_snapshot, excluded_paths)

          drop_excluded_and_orphaned_outputs(site, changed_pages, excluded_pages, old_output_paths, output_dir)
          relinked_counterparts = relink_counterparts(site)

          all_pages = (site.pages + site.sections).as(Array(Models::Page))

          # The winner map above was claimed before the exclusion pass and the
          # relink: a page just drafted still owned its URL, and an alias the
          # relink added (the versioned parent stub a drafted `docs/_index.md`
          # hands to the latest root) lost to it and was never written. Re-claim
          # from the page set that will actually render — as run_rerender does.
          unless excluded_pages.empty? && relinked_counterparts.empty?
            @output_url_winners = compute_output_url_winners(all_pages)
          end

          # Rebuild lookup index (page data may have changed)
          site.build_lookup_index

          # Re-link the global reading order; `renav_pages` is every page whose
          # prev/next pointer actually changed (a section weight/sort/reverse edit
          # reorders a whole block, not just the edited page's neighbors).
          renav_pages = relink_navigation_for_sections(site, affected_sections)

          # Recompute series for affected series (if enabled), including old memberships
          affected_series = if site.config.series.enabled
                              recompute_series_for_pages(site, changed_pages, old_series_names)
                            else
                              Set(String).new
                            end

          # Recompute related posts selectively (if enabled). Pass the excluded
          # pages' paths so pages that listed a now-removed page as related drop it.
          related_pages_updated = recompute_related_posts_for_pages(site, changed_pages, excluded_paths)
          compute_backlinks(site) if site.config.backlinks

          # Invalidate Crinja caches for affected pages/sections
          invalidate_caches_for_pages(changed_pages, affected_sections)
          invalidate_caches_for_pages(relinked_counterparts, Set(String).new) unless relinked_counterparts.empty?
          @crinja_cache_mutex.synchronize do
            @series_crinja_cache.reject! { |key, _| affected_series.includes?(key[0]) } unless affected_series.empty?
            related_pages_updated.each { |path| @related_posts_crinja_cache.delete(path) }

            # A changed SECTION's title/url is embedded in every descendant's
            # breadcrumb, which is served from @ancestors_crinja_cache keyed
            # {section, language}. affected_sections only covers the section
            # itself and its UPWARD ancestors, so drop the whole DESCENDANT
            # subtree ("sec" and "sec/...") too, or re-rendered descendants
            # would read a cached ancestors array still carrying the old
            # title/url.
            changed_pages.each do |page|
              next unless page.is_a?(Models::Section)
              sec = page.section
              @ancestors_crinja_cache.reject! { |k, _| k[0] == sec || k[0].starts_with?("#{sec}/") }
            end
          end

          # --- 3. Determine the full set of pages that need re-rendering ---
          pages_to_render = relationship_render_set(site, pages_map, reparsed, changed_pages,
            relinked_counterparts, renav_pages, affected_series, related_pages_updated)
          backlinks_moved_pages(site, templates, backlink_digests).each { |p| pages_to_render << p }

          # Pages that render a listing derived from the GLOBAL page/section
          # set — the homepage's "latest posts", a paginated archive, a nav
          # built from `site.menus`, a sidebar reading `get_section(X).pages`.
          # None of them own the edited page, so none of the selections above
          # reach them, and their on-disk HTML kept showing the pre-edit title
          # (or kept listing a page just flipped to draft) until something
          # unrelated happened to re-render them.
          listing_fanout_pages(site, templates, all_pages, listing_sets)
            .each { |p| pages_to_render << p }

          render_list = pages_to_render.to_a

          # --- 4. Re-render the affected pages ---
          global_vars = build_global_vars(site, options.cache_busting)
          # Refresh the stash render_global_vars_or_build serves — taxonomy
          # pages regenerated below (and any later 404 rebuild) would
          # otherwise render against the site snapshot of the last FULL
          # build: old titles, old term sets, old menus.
          @render_global_vars = global_vars
          @pages_by_path = build_pages_by_path(site)
          cache = @cache || Cache.new(enabled: false)

          # Render in parallel like run_rerender/the cold build — a section
          # `_index` edit re-renders its whole subtree, and doing that one
          # page at a time made large-section edits the slowest watch path.
          # process_files_sequential mirrors the old per-page loop exactly
          # (render_page + record_page_cache_entry).
          error_overlay = options.error_overlay
          renderable_list = render_list.select(&.render)
          if options.parallel && renderable_list.size > 1
            process_files_parallel(renderable_list, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
          else
            process_files_sequential(renderable_list, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
          end
          raise_on_broken_internal_links!(output_dir)
          regenerate_amp_mirrors(renderable_list, site, output_dir, verbose)

          sweep_stale_derived_outputs(output_dir)
          cache.save if options.cache

          # The 404 page renders site-wide listings too (a docs sidebar, the
          # nav) and is never in the render set above — regenerate it so it
          # doesn't keep printing the pre-edit titles. One page; always cheap.
          generate_404_page(site, templates, output_dir, minify, verbose, global_vars)

          # --- 5. Regenerate taxonomy index/term pages ---
          # Merge the generated taxonomy pages into the page set the SEO
          # generators read so taxonomy.sitemap/feed take effect on incremental
          # rebuilds too (mirrors the lifecycle taxonomy hook). `all_pages` is
          # left intact for the rebuild summary below.
          taxonomy_sections = Content::Taxonomies.generate(site, output_dir, templates, verbose, builder: self)
          seo_pages = taxonomy_sections.empty? ? all_pages : all_pages + taxonomy_sections

          # --- 6. Regenerate lightweight SEO / search files in parallel ---
          regenerate_seo_surfaces(seo_pages, site, output_dir, verbose, options.parallel, include_robots: true, options: options)
          write_html_stats(complete: false)

          elapsed = Time.instant - start_time
          Logger.outcome("rebuilt", "#{render_list.size}/#{all_pages.size} pages", :result, elapsed.total_milliseconds)
          report_cache_stats(options.verbose)
          true
        end

        # Incremental parse of changed content + full re-render with reloaded templates.
        # Used when both content and templates changed simultaneously.
        def run_incremental_then_rerender(changed_content_files : Array(String), options : Config::Options::BuildOptions) : Bool
          @render_workers = options.workers
          config = @config
          site = @site

          unless config && site
            return run(options)
          end

          Logger.info "Re-parsing #{changed_content_files.size} changed file(s) before full re-render..."
          begin_serve_pass

          output_dir = options.output_dir
          pages_map = @pages_by_path || build_pages_by_path(site)

          # Projection digests taken before the re-parse, exactly as in
          # run_incremental — the re-render below is selective too, so a
          # listing page the template edit doesn't touch needs the same
          # fan-out. Snapshotted against the CURRENT templates: run_rerender
          # reloads them, but both sides of the comparison then use the same
          # `needs_*` answer, and a template edit that changes which
          # projections exist re-renders on its own account anyway.
          listing_sets = snapshot_listing_sets(site, @templates)
          backlink_digests = snapshot_backlinks(site, @templates)

          reparsed = reparse_changed_pages(changed_content_files, site, config, output_dir, pages_map)
          return run(options) unless reparsed
          changed_pages = reparsed.changed_pages
          affected_sections = reparsed.affected_sections
          old_output_paths = reparsed.old_output_paths

          # Exclusion pass, mirroring run_incremental: a save that flips a
          # page to draft (or into the expired/future window) alongside a
          # template edit used to leave it published — still in listings,
          # feeds, and on disk — because only the content-only strategy
          # applied the filters.
          excluded_pages = apply_publication_exclusions!(changed_pages, options)
          excluded_paths = excluded_pages.map(&.path).to_set

          # Deferred permalink errors — mirrors run_incremental.
          raise_on_permalink_errors!(changed_pages)

          # Update all derived relationships before full re-render (removal
          # runs for every re-parsed page; excluded pages' new terms are not
          # re-added — see update_taxonomies_incremental).
          update_taxonomies_incremental(site, changed_pages + excluded_pages, reparsed.old_taxonomies_snapshot, excluded_paths)

          drop_excluded_and_orphaned_outputs(site, changed_pages, excluded_pages, old_output_paths, output_dir)
          relinked_counterparts = relink_counterparts(site)
          invalidate_caches_for_pages(relinked_counterparts, Set(String).new) unless relinked_counterparts.empty?

          site.build_lookup_index
          renav_pages = relink_navigation_for_sections(site, affected_sections)
          affected_series = if site.config.series.enabled
                              recompute_series_for_pages(site, changed_pages, reparsed.old_series_names)
                            else
                              Set(String).new
                            end
          related_pages_updated = recompute_related_posts_for_pages(site, changed_pages, excluded_paths)
          refresh_wikilink_index((site.pages + site.sections).as(Array(Models::Page)), site)
          compute_backlinks(site) if site.config.backlinks

          # Re-render with reloaded templates. The selective path inside
          # run_rerender only covers template-affected pages, so the content
          # pages re-parsed above — and every page whose neighbours, series
          # or related posts they moved, exactly as run_incremental selects
          # them — must be forced into the render set.
          #
          # membership_changed: a page whose draft/expired/future status just
          # flipped it OUT of the built set leaves changed_pages (so
          # force_pages can't carry the signal), yet sitemap/feeds/search and
          # taxonomy pages still list it — run_rerender must refresh those
          # surfaces even when the template edit itself was layout-only (or a
          # bare mtime touch). Flips INTO the set escalate to a full rebuild
          # via the pages_map miss above, so exclusions are the only
          # membership change this path can see.
          force_pages = relationship_render_set(site, pages_map, reparsed, changed_pages,
            relinked_counterparts, renav_pages, affected_series, related_pages_updated)
          backlinks_moved_pages(site, @templates, backlink_digests).each { |p| force_pages << p }
          run_rerender(options, force_pages: force_pages.to_a, membership_changed: !excluded_pages.empty?,
            listing_sets: listing_sets)
        end

        # The pages a content re-parse must re-render because a relationship
        # moved: the changed pages, their translations/versions, the section
        # indexes that list them (a changed `_index` takes its whole subtree),
        # their old and new reading-order neighbours, every member of a series
        # they joined or left, and every page whose related posts were
        # recomputed. Shared by both content strategies — the content+template
        # path used to force only the changed pages through its re-render, so
        # a neighbour kept linking the old title and URL (a deleted file after
        # a slug edit) for the rest of the session.
        private def relationship_render_set(
          site : Models::Site,
          pages_map : Hash(String, Models::Page),
          reparsed : ReparsedPages,
          changed_pages : Array(Models::Page),
          relinked_counterparts : Array(Models::Page),
          renav_pages : Enumerable(Models::Page),
          affected_series : Set(String),
          related_pages_updated : Enumerable(String),
        ) : Set(Models::Page)
          pages_to_render = Set(Models::Page).new(changed_pages)
          # Translations / other versions whose switcher (or canonical) moved.
          relinked_counterparts.each { |p| pages_to_render << p }

          # Section index pages whose content lists include the changed pages.
          # Include every language variant of the section (multilingual sites
          # have one `_index.<lang>.md` per language under the same path).
          reparsed.affected_sections.each do |section_name|
            site.sections.each do |section|
              pages_to_render << section if section.section == section_name
            end
          end

          # When a SECTION `_index` itself changed, its own title/url can appear
          # in every descendant page's breadcrumb (page.ancestors) and its sort
          # settings reorder the section's listings — so re-render the whole
          # subtree. Cover BOTH descendant content pages (site.pages) AND nested
          # section index pages (site.sections — `_index.md` files never live in
          # site.pages), or a nested subsection's breadcrumb stays stale. Bounded
          # by the edited section's size, and only triggered by the rarer section
          # edits.
          changed_pages.each do |page|
            next unless page.is_a?(Models::Section)
            sec = page.section
            prefix = "#{sec}/"
            site.pages.each do |p|
              pages_to_render << p if p.section == sec || p.section.starts_with?(prefix)
            end
            site.sections.each do |s|
              pages_to_render << s if s.section == sec || s.section.starts_with?(prefix)
            end
          end

          # Previous / next pages. `renav_pages` is every page whose lower/higher
          # pointer changed in the global re-link (covers block reorders from a
          # section weight/sort/reverse edit); the explicit old/new neighbors of
          # each changed page are a subset but kept for clarity.
          renav_pages.each { |p| pages_to_render << p }
          changed_pages.each do |page|
            # New neighbors (after re-link)
            page.lower.try { |l| pages_to_render << l }
            page.higher.try { |h| pages_to_render << h }

            # Old neighbors (before re-link, may have shifted)
            if old = reparsed.old_neighbors[page.path]?
              old[0].try { |l| pages_to_render << l }
              old[1].try { |h| pages_to_render << h }
            end
          end

          # Pages in affected series (their series_index may have changed)
          unless affected_series.empty?
            site.pages.each do |p|
              pages_to_render << p if p.series && affected_series.includes?(p.series)
            end
          end

          # Pages whose related_posts were recomputed
          related_pages_updated.each do |path|
            if p = pages_map[path]?
              pages_to_render << p
            end
          end
          pages_to_render
        end

        # Re-run the counterpart linkers — `Multilingual.link_translations!`
        # and `Versions.link!` — over the live page set, exactly as the full
        # parse does, and return every page whose links moved. A page's
        # language switcher, hreflang alternates, version switcher and (for
        # an old version) canonical are all derived from its COUNTERPARTS: a
        # counterpart that was re-slugged, retitled, drafted or turned
        # `render = false` changes pages the edit never touched, which kept
        # linking to (and canonicalizing on) a URL that no longer existed
        # until the next full rebuild.
        private def relink_counterparts(site : Models::Site) : Array(Models::Page)
          config = site.config
          return [] of Models::Page unless config.multilingual? || config.versions.enabled?
          pages = (site.pages + site.sections).as(Array(Models::Page))
          # Every field the two linkers write: `link_translations!` sets
          # `translations`; `Versions.link!` sets `version_links` and, with
          # `latest_at_root = false`, adds the parent-URL alias to the latest
          # version's root — which appears when an authored parent index
          # (`docs/_index.md`) is drafted, and must re-render the root or the
          # stub a cold build writes is missing until a full rebuild.
          before = pages.map { |page| {page.translations.dup, page.version_links.dup, page.aliases.dup} }
          Content::Multilingual.link_translations!(pages, config)
          Content::Versions.link!(pages, config)
          moved = [] of Models::Page
          pages.each_with_index do |page, i|
            moved << page if {page.translations, page.version_links, page.aliases} != before[i]
          end
          moved
        end

        # Each backlink-reading page's backlinks digest (fp_backlinks), taken
        # before a re-parse so backlinks_moved_pages can diff it afterwards.
        # Empty unless `[content] backlinks`.
        private def snapshot_backlinks(site : Models::Site, templates : Hash(String, String)?) : Hash(String, String)
          digests = {} of String => String
          return digests unless templates && site.config.backlinks
          (site.pages + site.sections).each do |page|
            digest = backlinks_digest(page, site, templates)
            digests[page.path] = digest if digest
          end
          digests
        end

        # Pages whose rendered backlinks this re-parse moved: A adding or
        # dropping a link to B, or A's listed fields changing, re-renders B.
        private def backlinks_moved_pages(site : Models::Site, templates : Hash(String, String)?, before : Hash(String, String)) : Array(Models::Page)
          return [] of Models::Page unless templates && site.config.backlinks
          (site.pages + site.sections).select do |page|
            digest = backlinks_digest(page, site, templates)
            digest && digest != before[page.path]?
          end
        end

        private def backlinks_digest(page : Models::Page, site : Models::Site, templates : Hash(String, String)) : String?
          rel = page_template_scan(page, templates, site).relations
          return unless rel.backlinks
          digest = Digest::MD5.new
          fp_backlinks(digest, page, rel.fields)
          digest.final.hexstring
        end

        # Digests of every page-set projection the site's templates read,
        # taken before a re-parse so the fan-out can diff them afterwards.
        # `needs_*` records which ones any template actually reads; the rest
        # are left empty and never computed — the page-set digest is O(pages)
        # and must not be paid by a site with no listing at all.
        private record ListingSetSnapshot,
          needs_page : Bool,
          needs_section : Bool,
          needs_menu : Bool,
          needs_taxonomy : Bool,
          page : String,
          section : String,
          menu : String,
          taxonomy : String,
          lookup_targets : Array(String) = [] of String,
          lookup_fields : ListingPageFields = ListingPageFields.new(false, false),
          lookup : String = "" do
          def self.inert : ListingSetSnapshot
            new(false, false, false, false, "", "", "", "")
          end
        end

        # Snapshot the projections before a re-parse. `templates` is nil only
        # before the first build, where there is nothing to fan out to —
        # returning `inert` also keeps a throwaway Hash out of
        # `listing_source_union`, which memoizes on the hash's object_id.
        private def snapshot_listing_sets(site : Models::Site, templates : Hash(String, String)?) : ListingSetSnapshot
          return ListingSetSnapshot.inert unless templates

          blob = templates.values.join("\n")
          needs_page = Phases::Render::LISTING_PAGE_MARKERS.any? do |marker|
            marker == "get_taxonomy" ? Phases::Render::GET_TAXONOMY_RE.matches?(blob) : blob.includes?(marker)
          end || dynamic_get_page?(blob)
          # A section index renders its own page list with no marker to scan
          # for (`{{ section.list }}`), so any site with sections can need the
          # page digest.
          needs_page ||= !site.sections.empty?
          needs_section = Phases::Render::LISTING_SECTION_MARKERS.any? { |marker| blob.includes?(marker) }
          needs_menu = Phases::Render::MENU_SET_MARKERS.any? { |marker| blob.includes?(marker) }
          needs_taxonomy = blob.includes?(Phases::Render::TAXONOMY_URL_MARKER)
          # The pages literal `get_page(path=...)` calls fetch: their own
          # projection, so a footer printing the about page's title refreshes
          # when the about page moves and not on every other edit.
          lookup_targets = get_page_targets(blob)
          lookup_fields = relation_page_fields(blob)

          ListingSetSnapshot.new(
            needs_page: needs_page,
            needs_section: needs_section,
            needs_menu: needs_menu,
            needs_taxonomy: needs_taxonomy,
            page: needs_page ? compute_page_set_fingerprint(site.pages, listing_page_fields(templates)) : "",
            section: needs_section ? compute_section_set_fingerprint(site.sections, !site.config.menus_auto_sections.nil?) : "",
            menu: needs_menu ? compute_menu_set_fingerprint(site) : "",
            taxonomy: needs_taxonomy ? compute_taxonomy_slug_fingerprint(site) : "",
            lookup_targets: lookup_targets,
            lookup_fields: lookup_fields,
            lookup: compute_get_page_lookup_fingerprint(site, lookup_targets, lookup_fields),
          )
        end

        # Pages that render a projection of the global page/section set which
        # THIS rebuild actually moved.
        #
        # `hwaro build --cache` solves the same problem in
        # `filter_changed_pages` and serve had no equivalent, so a retitled
        # post left the homepage showing the old title for the rest of the
        # session. The difference is granularity, and it is not cosmetic: the
        # cached build gates every marker on one broad page-set digest, which
        # for a site whose base layout carries a nav (`get_menu`) and whose
        # posts carry tag pills (`get_taxonomy_url`) selects EVERY page on any
        # metadata edit. A full build re-renders the union anyway; a dev server
        # turning each keystroke-save into a whole-site render does not.
        #
        # So each marker class is gated on a digest of what it actually reads
        # (see the marker constants in phases/render/fingerprints.cr). A nav
        # re-renders when a menu entry moves, a tag pill when the term set
        # does, and a `site.pages` listing when the page set does — which is
        # also the edit where re-rendering it is the whole point.
        private def listing_fanout_pages(
          site : Models::Site,
          templates : Hash(String, String),
          all_pages : Array(Models::Page),
          before : ListingSetSnapshot,
        ) : Array(Models::Page)
          page_changed = before.needs_page &&
                         compute_page_set_fingerprint(site.pages, listing_page_fields(templates)) != before.page
          section_changed = before.needs_section &&
                            compute_section_set_fingerprint(site.sections, !site.config.menus_auto_sections.nil?) != before.section
          menu_changed = before.needs_menu &&
                         compute_menu_set_fingerprint(site) != before.menu
          taxonomy_changed = before.needs_taxonomy &&
                             compute_taxonomy_slug_fingerprint(site) != before.taxonomy
          lookup_changed = !before.lookup_targets.empty? &&
                           compute_get_page_lookup_fingerprint(site, before.lookup_targets, before.lookup_fields) != before.lookup

          return [] of Models::Page unless page_changed || section_changed || menu_changed || taxonomy_changed || lookup_changed

          all_pages.select do |page|
            next false unless page.render
            # The page's whole render closure: entry template, the shortcodes
            # its content calls (`{{ recent() }}` looping a section's pages
            # is a listing too, and its output lives in the page CONTENT,
            # which a re-render rebuilds) and its output-format templates.
            deps = page_template_scan(page, templates, site).listing
            # Mirrors filter_changed_pages: a section index renders its
            # section's page list even via `{{ section.list }}`, which leaves
            # no marker in the template source to scan for.
            page_dep = deps.page || page.is_a?(Models::Section)
            (page_dep && page_changed) ||
              (deps.section && section_changed) ||
              (deps.menu && menu_changed) ||
              (deps.taxonomy_slug && taxonomy_changed) ||
              (deps.lookup && lookup_changed)
          end
        end

        # Everything the incremental strategies need to know about the pages a
        # save touched, captured BEFORE they were re-parsed (old taxonomy terms
        # to retract, old series, old reading-order neighbours, old output
        # files to delete on relocation).
        private record ReparsedPages,
          changed_pages : Array(Models::Page),
          affected_sections : Set(String),
          old_taxonomies_snapshot : Hash(String, Hash(String, Array(String))),
          old_series_names : Hash(String, String?),
          old_output_paths : Hash(String, Array(String)),
          old_neighbors : Hash(String, {Models::Page?, Models::Page?})

        # Re-parse the changed content files in place (front matter, URL,
        # cascade defaults) and snapshot their pre-edit state. Shared by the
        # content-only and content+template incremental strategies.
        #
        # Returns nil when the edit is beyond incremental bookkeeping — a file
        # that is not in the site model (an excluded page that may have just
        # become publishable, or a filtered section _index whose [cascade]
        # still reaches descendants) or a changed section [cascade] — and the
        # caller must run a full build. nil is a sentinel distinct from "no
        # matching pages": that is a normal, empty result.
        private def reparse_changed_pages(
          changed_content_files : Array(String),
          site : Models::Site,
          config : Models::Config,
          output_dir : String,
          pages_map : Hash(String, Models::Page),
        ) : ReparsedPages?
          changed_pages = [] of Models::Page
          affected_sections = Set(String).new
          old_taxonomies_snapshot = {} of String => Hash(String, Array(String))
          old_series_names = {} of String => String?
          # Output files each changed page occupied BEFORE re-parse — a slug/
          # custom_path edit relocates the page, and the original file would
          # otherwise keep serving 200 for the rest of the session (and ship
          # if `public/` is deployed from it).
          old_output_paths = {} of String => Array(String)

          # Snapshot old neighbors before re-linking (for render set)
          old_neighbors = {} of String => {Models::Page?, Models::Page?}

          # Cascade context for re-applying section defaults to re-parsed pages
          # (parse_single_page resets fields from front matter only). Prefer
          # the cold build's pre-filter map: it still contains cascades from
          # draft/expired _index sections that site.sections no longer holds.
          cascade_map = @cascade_map || build_cascade_map(site.sections)

          changed_content_files.each do |file|
            relative_path = path_relative_to(file, "content")

            page = pages_map[relative_path]?
            unless page
              # Not in the site model: an excluded page (draft / future /
              # expired / parse-failed at startup) whose edit may have just
              # made it publishable, or a filtered section _index whose
              # [cascade] still reaches descendants. Incremental bookkeeping
              # can't see either — un-drafting a post used to be silently
              # skipped here until serve restart. A full rebuild re-admits
              # whatever this save changed. Files gone from disk are the
              # watcher's removed-file path; still skip those.
              if File.exists?(file)
                Logger.info "  Changed #{relative_path} is not in the site model — running full rebuild."
                return
              end
              next
            end

            # Snapshot before re-parse (includes property-backed taxonomies
            # like authors — see snapshot_page_taxonomies)
            old_taxonomies_snapshot[page.path] = snapshot_page_taxonomies(page, site)
            old_series_names[page.path] = page.series
            old_neighbors[page.path] = {page.lower, page.higher}
            old_cascade = page.is_a?(Models::Section) ? page.cascade : nil
            old_output_paths[page.path] = collect_page_output_paths(page, output_dir)
            @unsettled_page_outputs.concat(old_output_paths[page.path])

            # Re-read, re-parse front-matter and recalculate URL
            parse_single_page(page)
            page.generate_permalink(config.base_url)
            # Content (shortcode usage) or front-matter template may have changed
            @page_template_hash_mutex.synchronize { @page_template_hash_memo.delete(page.path) }

            # A changed [cascade] affects descendant pages that are NOT in the
            # changed set — incremental bookkeeping can't reach them, so
            # escalate to a full rebuild (rare event, correctness first).
            if (previous_cascade = old_cascade) && page.is_a?(Models::Section) && page.cascade != previous_cascade
              Logger.info "  Section cascade changed in #{page.path} — running full rebuild."
              return
            end

            apply_cascade_to(page, cascade_map)
            # A schema violation fails the build: let the full build report
            # it (every page, sorted) and set the overlay.
            unless apply_content_schema(page, config, cascade_map).empty?
              Logger.info "  #{page.path} violates its [[content.schema]] — running full rebuild."
              return
            end

            changed_pages << page
            affected_sections << page.section
            # Also include ancestor sections that may list this page
            page.ancestors.each { |ancestor| affected_sections << ancestor.section }
          end

          ReparsedPages.new(changed_pages, affected_sections, old_taxonomies_snapshot, old_series_names, old_output_paths, old_neighbors)
        end

        # Drop the re-parsed pages that the build options exclude (draft /
        # expired / future) from `changed_pages`, returning them. Same
        # contract as the full parse phase: the publication window is
        # re-stamped first so pages kept via --include-future /
        # --include-expired stay out of public artifacts and listings.
        private def apply_publication_exclusions!(
          changed_pages : Array(Models::Page),
          options : Config::Options::BuildOptions,
        ) : Array(Models::Page)
          excluded_pages = [] of Models::Page
          now = Time.utc
          changed_pages.each(&.refresh_unpublished!(now))
          unless options.drafts
            excluded_pages.concat(changed_pages.select(&.draft))
            changed_pages.reject!(&.draft)
          end
          unless options.include_expired
            excluded_pages.concat(changed_pages.select { |p| p.expires.try { |e| e <= now } || false })
            changed_pages.reject! { |p| p.expires.try { |e| e <= now } || false }
          end
          unless options.include_future
            excluded_pages.concat(changed_pages.select { |p| p.date.try { |d| d > now } || false })
            changed_pages.reject! { |p| p.date.try { |d| d > now } || false }
          end
          excluded_pages
        end

        # Remove excluded pages from the site indices and delete every output
        # file the edit orphaned: the excluded pages' files, and for the
        # surviving pages the set difference between their old and new output
        # paths — a relocation (slug/custom_path change) moves EVERY output,
        # but a front-matter edit can also drop just a sibling format
        # (`outputs = ["json"]` removed) while the primary path stays put.
        private def drop_excluded_and_orphaned_outputs(
          site : Models::Site,
          changed_pages : Array(Models::Page),
          excluded_pages : Array(Models::Page),
          old_output_paths : Hash(String, Array(String)),
          output_dir : String,
        ) : Nil
          unless excluded_pages.empty?
            excluded_paths = excluded_pages.map(&.path).to_set
            site.pages.reject! { |p| excluded_paths.includes?(p.path) }
            site.sections.reject! { |p| excluded_paths.includes?(p.path) }
            excluded_pages.each do |p|
              stale = old_output_paths[p.path]? || [get_output_path(p, output_dir)].compact
              prune_unclaimed_outputs(stale, output_dir)
            end
          end

          relocated = [] of String
          changed_pages.each do |page|
            next unless olds = old_output_paths[page.path]?
            relocated.concat(olds - collect_page_output_paths(page, output_dir))
          end
          prune_unclaimed_outputs(relocated, output_dir) unless relocated.empty?
          settle_page_outputs(output_dir, except: old_output_paths.values.flatten)
        end

        # Prune what an earlier pass that raised after its re-parse left
        # unsettled (see `@unsettled_page_outputs`) — less `except`, the
        # paths the caller has just settled itself — and empty the set.
        private def settle_page_outputs(output_dir : String, except : Array(String) = [] of String) : Nil
          return if @unsettled_page_outputs.empty?
          leftover = @unsettled_page_outputs.to_a - except
          @unsettled_page_outputs.clear
          prune_unclaimed_outputs(leftover.sort!, output_dir) unless leftover.empty?
        end

        # Re-render pages using reloaded templates without re-parsing content.
        # Useful when only template files have been modified. With template
        # dependency tracking active, only the pages whose template closure
        # includes an edited template are re-rendered; otherwise (tracking
        # off, a dynamic include in the graph, or templates added/removed)
        # every page re-renders as before.
        #
        # `force_pages` are rendered regardless of template impact — callers
        # that re-parsed content (run_incremental_then_rerender) pass them so
        # the selective path can't skip a content-changed page. Their taxonomy
        # membership may have changed too, so taxonomy pages regenerate
        # whenever force_pages are present.
        #
        # `membership_changed` signals that pages left the built set in this
        # pass (a draft/expired/future flip): the SEO surfaces and taxonomy
        # pages must refresh even when no template content changed, and the
        # identical-templates early return must not skip that work.
        #
        # `listing_sets` is the caller's pre-re-parse snapshot of the page-set
        # projections (see snapshot_listing_sets): the selective render set
        # must also take in the listing pages that print a projection the
        # content re-parse moved. Nil for a pure template edit, which changes
        # no page metadata.
        def run_rerender(
          options : Config::Options::BuildOptions,
          force_pages : Array(Models::Page)? = nil,
          membership_changed : Bool = false,
          listing_sets : ListingSetSnapshot? = nil,
        ) : Bool
          @render_workers = options.workers
          config = @config
          site = @site

          unless config && site
            return run(options)
          end

          start_time = Time.instant
          begin_serve_pass
          clear_broken_internal_links

          # Reload templates from disk & reset all runtime caches.
          # Keep the old sources so the dependency graph can diff them.
          old_templates = @templates
          old_shadowed = @shadowed_template_hashes
          @templates = nil
          @cache_manager.clear_runtime
          templates = load_templates
          @templates = templates

          # Refresh invalidation mode for the reloaded template set. Mirror
          # phases/initialize.cr: snapshot-escaping refs (./-prefixed,
          # non-template extensions, shadowed exact-ext variants) are read
          # from disk at render time, so their contents must be folded into
          # the global hash here too — otherwise serve rerenders and
          # `build --cache` disagree on every page's cache entry.
          deps = @template_deps
          @global_templates_hash = Cache.compute_templates_hash(templates)
          if (graph = deps) && !graph.snapshot_escaping_refs.empty?
            @global_templates_hash = fold_snapshot_escaping_refs(@global_templates_hash, graph.snapshot_escaping_refs)
          end
          @per_page_template_hash = config.build.template_deps &&
                                    (deps.try { |d| !d.dynamic? } || false)

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose

          all_pages = (site.pages + site.sections).as(Array(Models::Page))
          renderable_pages = all_pages.select(&.render)

          # Selective re-render: same template set, fully static graph.
          # `old_shadowed` guards extension-shadowed variants (foo.j2 next to
          # foo.html): they aren't in the snapshot hash, but an explicit
          # `{% include "foo.j2" %}` reads them from disk — an edit there
          # used to hit the "contents are identical" early return forever.
          affected_templates : Set(String)? = nil
          changed_template_names : Set(String)? = nil
          # True when the change can alter page CONTENT and summaries
          # (shortcode/hook templates in the affected closure), not just the
          # layout — drives the summary recompute and SEO-surface refresh.
          content_semantics_changed = false
          if @per_page_template_hash && deps && old_templates &&
             old_templates.keys.sort! == templates.keys.sort! &&
             old_shadowed == @shadowed_template_hashes
            changed = Set(String).new
            templates.each do |name, source|
              changed << name if old_templates[name]? != source
            end
            changed_template_names = changed
            if changed.empty? && (force_pages.nil? || force_pages.empty?) && !membership_changed
              Logger.info "Template change detected, but contents are identical — nothing to re-render."
              return true
            end
            affected = deps.dependents_closure(changed)
            if affected.any? { |n| n.starts_with?("hooks/") || n.starts_with?("shortcodes/") }
              # Hook templates aren't in the {% include %}/{% extends %}
              # dependency graph (they're invoked from Markdown rendering,
              # not template rendering), and shortcode output is embedded in
              # page content AND summaries that listing pages and feeds
              # re-print — the per-page graph can't scope either, so fall
              # back to a full re-render. Checking the CLOSURE (not just the
              # changed set) also catches a partial included by a
              # shortcode/hook template.
              affected_templates = nil
              content_semantics_changed = true
            else
              affected_templates = affected
            end
            Logger.info "Template change detected (#{changed.join(", ")}). Re-rendering affected pages..." if options.verbose && !changed.empty?
          else
            Logger.info "Template change detected. Re-rendering all pages..." if options.verbose
          end

          pages_to_render = if affected_templates && deps
                              selected = renderable_pages.select do |page|
                                entry = determine_template(page, templates, site)
                                affected_templates.includes?(entry) ||
                                  deps.shortcodes_used_in(page.raw_content).any? { |sc| affected_templates.includes?(sc) } ||
                                  format_templates_affected?(page, templates, site, affected_templates)
                              end
                              seen = selected.map(&.path).to_set
                              if forced = force_pages
                                forced.each do |page|
                                  selected << page if page.render && seen.add?(page.path)
                                end
                              end
                              if sets = listing_sets
                                listing_fanout_pages(site, templates, all_pages, sets)
                                  .each { |page| selected << page if seen.add?(page.path) }
                              end
                              selected
                            else
                              renderable_pages
                            end

          if options.verbose && affected_templates && pages_to_render.size < renderable_pages.size
            Logger.info "  #{pages_to_render.size} of #{renderable_pages.size} pages affected."
          end

          global_vars = build_global_vars(site, options.cache_busting)
          # Refresh the stash render_global_vars_or_build serves — the 404
          # page and taxonomy regeneration below would otherwise render
          # against the site snapshot of the last FULL build.
          @render_global_vars = global_vars
          @pages_by_path = build_pages_by_path(site)
          cache = @cache || Cache.new(enabled: false)

          # Recompute <!-- more --> summaries with the reloaded templates —
          # but only when they can actually change: a shortcode/hook template
          # anywhere in the affected closure (content_semantics_changed), an
          # unclassifiable template change (changed_template_names nil), or
          # force_pages arriving from run_incremental_then_rerender with
          # summary_html reset to nil by parse_single_page. A layout-only
          # edit skips the recompute entirely (it can't affect summaries and
          # would re-run per-page Crinja work on every keystroke).
          forced = force_pages || [] of Models::Page
          summaries_affected = !forced.empty? ||
                               changed_template_names.nil? ||
                               content_semantics_changed
          if summaries_affected
            # force_pages with render:true are already in pages_to_render;
            # render:false ones are excluded from the render set but their
            # summaries still feed listings and feeds.
            summary_pages = pages_to_render + forced.reject(&.render)
            render_page_summaries(summary_pages, site, templates, highlight,
              link_targets: all_pages, global_vars: global_vars)

            # The Crinja value caches and `global_vars` above were built
            # BEFORE the recompute, so they still embed the OLD summary_html
            # — a listing page printing `{{ p.summary }}` would re-render
            # with the stale output (page body new, its summary everywhere
            # else old). Drop the page-value caches and rebuild the globals
            # from the fresh summaries.
            @crinja_cache_mutex.synchronize do
              @page_crinja_value_cache.clear
              @section_pages_crinja_cache.clear
              @section_pages_url_index_cache.clear
            end
            global_vars = build_global_vars(site, options.cache_busting)
            @render_global_vars = global_vars
          end

          # Re-claim output URLs (see run_incremental): forced content edits
          # may have introduced or resolved a slug/alias collision.
          @output_url_winners = compute_output_url_winners(all_pages)

          # User feed templates (rss.xml/atom.xml overrides) are not entry
          # templates for any page, so an edit to one — or to a partial they
          # include (dependents_closure above already folded includes) —
          # selects ZERO pages to re-render. The feed output still changed:
          # force the SEO-surface refresh and per-term taxonomy feed
          # regeneration below. Nil affected_templates means "anything may
          # have changed", which both conditions already treat as affected.
          feed_templates_affected = affected_templates.nil? ||
                                    Content::Seo::Feeds::FEED_TEMPLATE_KEYS.values.any? { |key| affected_templates.includes?(key) }

          error_overlay = options.error_overlay
          count = if pages_to_render.empty?
                    0
                  elsif options.parallel && pages_to_render.size > 1
                    process_files_parallel(pages_to_render, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
                  else
                    process_files_sequential(pages_to_render, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: error_overlay, profiler: active_profiler)
                  end
          raise_on_broken_internal_links!(output_dir)
          regenerate_amp_mirrors(pages_to_render, site, output_dir, verbose)

          # Re-generate the 404 page with the new template — and whenever
          # content moved: it renders the same site-wide listings (a docs
          # sidebar, the nav) as every other page, so a retitled page or
          # section left it printing the old names.
          if affected_templates.nil? || affected_templates.includes?("404") ||
             (force_pages && !force_pages.empty?) || membership_changed
            generate_404_page(site, templates, output_dir, minify, verbose, global_vars)
          end

          # Re-generate taxonomy pages with new templates. Their template
          # resolution falls back taxonomy_term -> taxonomy -> page, so any
          # of those being affected triggers the regeneration. Forced content
          # pages may have changed taxonomy membership — regenerate then too.
          taxonomy_sections = if affected_templates.nil? ||
                                 (force_pages && !force_pages.empty?) ||
                                 membership_changed ||
                                 feed_templates_affected ||
                                 ["taxonomy", "taxonomy_term", "page"].any? { |name| affected_templates.includes?(name) }
                                Content::Taxonomies.generate(site, output_dir, templates, verbose, builder: self)
                              else
                                [] of Models::Section
                              end

          # Content semantics changed in this pass — either re-parsed content
          # (run_incremental_then_rerender) or shortcode/hook template edits
          # that rewrote the page.content / summary_html that sitemap, feeds,
          # search, and llms embed. Refresh those surfaces. A pure layout
          # edit still skips this — template output doesn't feed them —
          # UNLESS the edit touched a user feed template, whose output IS a
          # generated surface (see feed_templates_affected above) — or pages
          # LEFT the built set this pass (membership_changed): sitemap,
          # feeds, search and llms would keep listing them otherwise.
          if summaries_affected || feed_templates_affected || membership_changed
            seo_pages = (site.pages + site.sections).as(Array(Models::Page))
            seo_pages += taxonomy_sections unless taxonomy_sections.empty?
            regenerate_seo_surfaces(seo_pages, site, output_dir, verbose, options.parallel, include_robots: true, options: options)
          elsif site.config.pwa.enabled
            # A layout-only template edit rightly skips the SEO surfaces
            # (their inputs didn't change) — but it DID rewrite page HTML,
            # and sw.js content-hashes the precached pages' bytes, so the
            # service worker must still be refreshed. Warn-and-continue,
            # matching regenerate_seo_surfaces: a transient failure here
            # must not skip cache.save below.
            begin
              Content::Seo::Pwa.generate(site, output_dir, verbose)
            rescue ex
              Logger.warn "  PWA regeneration failed: #{ex.message}"
            end
          end

          sweep_stale_derived_outputs(output_dir)
          cache.save if options.cache
          write_html_stats(complete: false)

          elapsed = Time.instant - start_time
          Logger.outcome("rebuilt", "#{count} #{count == 1 ? "page" : "pages"} · re-render", :result, elapsed.total_milliseconds)
          report_cache_stats(verbose)
          true
        end

        # True when a modified template feeds a `[[content.generate]]`
        # `body_template` — the body template itself, or a partial it
        # (transitively) includes. Bodies are rendered while the content is
        # GENERATED (Read phase), so only a full build re-runs them: the
        # re-render strategies re-render pages from the bodies they already
        # hold, and the body file (often `.md`) is not even in the template
        # snapshot, so the edit read as "contents are identical".
        # `changed_paths` are watcher paths (`templates/gen/product.md`).
        def generate_body_template_changed?(changed_paths : Array(String)) : Bool
          config = @config
          return false unless config
          body_names = config.content_generate.compact_map(&.body_template)
          return false if body_names.empty? || changed_paths.empty?

          changed_files = changed_paths.map { |path| Path[path].normalize.to_s }.to_set
          changed_names = changed_paths.compact_map do |path|
            next unless path.starts_with?("templates/")
            path_relative_to(path, "templates").sub(TEMPLATE_EXTENSION_REGEX, "")
          end.to_set
          snapshot = @templates || {} of String => String

          body_names.any? do |name|
            # The body loads through the filesystem fallback, i.e. the
            # literal file under templates/.
            body_file = Path["templates", name].normalize.to_s
            next true if changed_files.includes?(body_file)
            next false unless File.file?(body_file)
            key = name.sub(TEMPLATE_EXTENSION_REGEX, "")
            graph = TemplateDeps.new(snapshot.merge({key => File.read(body_file)}))
            !(graph.closure(key) & changed_names).empty?
          end
        end

        # Are there any pages stashed by `--fast-start` waiting to render?
        # Server checks this to decide whether to spawn the background fiber.
        def has_deferred_pages? : Bool
          if pages = @deferred_pages
            !pages.empty?
          else
            false
          end
        end

        # Render pages that were skipped on the initial `--fast-start` build.
        # Runs after the dev server is already serving the priority subset,
        # so user-visible "ready" time stays bounded on large sites.
        # Regenerates SEO/search files at the end since feeds and the search
        # index pull from `page.content`, which was empty for deferred pages
        # during the initial Generate phase.
        #
        # Also runs the BeforeRender hooks for the remaining work the
        # cold pass deferred — OG image generation for non-priority pages
        # and image resizing for static/content_file globs + non-priority
        # page assets. Without this step those images never get produced
        # in a fast-start serve session until the user saves a file.
        def render_deferred(options : Config::Options::BuildOptions) : Int32
          @render_workers = options.workers
          pages = @deferred_pages
          return 0 if pages.nil? || pages.empty?

          site = @site
          templates = @templates
          unless site && templates
            Logger.warn "render_deferred called before initial build completed; skipping."
            return 0
          end

          Logger.info "Fast-start: background-rendering #{pages.size} deferred page(s)..."
          start_time = Time.instant
          begin_serve_pass

          output_dir = options.output_dir
          minify = options.minify
          highlight = options.highlight && site.config.highlight.enabled
          verbose = options.verbose
          cache = @cache || Cache.new(enabled: false)

          # Re-run the BeforeRender hooks against the full page set. The
          # ctx carries no priority_pages this time, so OG image
          # generation and image resizing process whatever the cold pass
          # left undone. We construct a fresh context rather than reusing
          # the original — the original's priority_pages would short-
          # circuit the very hooks we want to fully execute here.
          deferred_ctx = Lifecycle::BuildContext.new(options)
          deferred_ctx.site = site
          deferred_ctx.config = site.config
          deferred_ctx.pages = site.pages
          deferred_ctx.sections = site.sections
          deferred_ctx.templates = templates
          deferred_ctx.output_dir = output_dir
          deferred_ctx.priority_pages = nil
          deferred_ctx.profiler = @profiler if @profiler.try(&.enabled?)
          # Still a partial pass — the priority pass just wrote OG
          # manifest entries we must not truncate. Without this flag the
          # deferred pass would overwrite `.og_manifest.json` with only
          # its own slugs and the next cold start would re-render every
          # priority page's OG image from scratch.
          deferred_ctx.partial_render = true

          # Trigger BeforeRender hooks directly — we're not re-running the
          # Render phase, just the prep work it would have done.
          @lifecycle.trigger(Lifecycle::HookPoint::BeforeRender, deferred_ctx)

          global_vars = build_global_vars(site, options.cache_busting)
          # Keep the 404/taxonomy stash in sync (see run_incremental).
          @render_global_vars = global_vars
          @pages_by_path = build_pages_by_path(site)
          renderable = pages.select(&.render)

          count = if options.parallel && renderable.size > 1
                    process_files_parallel(renderable, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: options.error_overlay, profiler: active_profiler)
                  else
                    process_files_sequential(renderable, site, templates, output_dir, minify, cache, highlight, verbose, global_vars, error_overlay: options.error_overlay, profiler: active_profiler)
                  end
          # Strict [links] broken_internal = "error": this pass continues the
          # initial fast-start build, so don't clear here. If the priority
          # fan-out already raised, its entries are still in the accumulator
          # (raising never clears) and get re-reported alongside whatever the
          # deferred pages collected — acceptable: those links are still
          # broken, and @rebuild_failed escalates the next watch rebuild to a
          # full build, which clears at entry. The server's fast-start fiber
          # rescues this and routes it into the error overlay via
          # notify_build_error; the server keeps running.
          raise_on_broken_internal_links!(output_dir)
          regenerate_amp_mirrors(renderable, site, output_dir, verbose)

          # Refresh feeds / sitemap / search now that every page has rendered
          # content. Without this, feed descriptions and the search index
          # only cover the priority subset. Per-taxonomy RSS feeds and tag
          # listing pages pull from `page.content` too, so they have to be
          # regenerated for the same reason — matches `run_rerender`.
          # Regenerate taxonomy pages BEFORE the SEO surfaces and merge them
          # into the page set. Previously taxonomy generation ran after the
          # sitemap, so its pages never appeared in it (taxonomy.sitemap/feed
          # had no effect on this deferred pass).
          taxonomy_sections = Content::Taxonomies.generate(site, output_dir, templates, verbose, builder: self)
          all_pages = (site.pages + site.sections + taxonomy_sections).as(Array(Models::Page))
          regenerate_seo_surfaces(all_pages, site, output_dir, verbose, options.parallel, options: options)

          # Persist cache updates from the deferred pass. The initial build
          # already saved once; without this second save, killing the server
          # before any watch rebuild loses the deferred pages' cache entries
          # and the next `--cache` cold start has to re-render them.
          sweep_stale_derived_outputs(output_dir)
          cache.save if options.cache
          write_html_stats(complete: false)

          # Clear the stash so a second call is a no-op and subsequent
          # watch-triggered full rebuilds start clean.
          @deferred_pages = nil

          elapsed = Time.instant - start_time
          Logger.outcome("rendered", "#{count} deferred #{count == 1 ? "page" : "pages"}", :result, elapsed.total_milliseconds)
          count
        end
      end
    end
  end
end
