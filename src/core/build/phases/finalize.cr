# Phase: Finalize — stale-output pruning, cache save
#
# Handles the final phase of the build lifecycle:
# removing output a page no longer claims, then persisting the build cache
# to disk for future incremental builds.

module Hwaro::Core::Build::Phases::Finalize
  private def execute_finalize_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("Finalize")
    result = @lifecycle.run_phase(Lifecycle::Phase::Finalize, ctx) do
      build_cache = @cache || raise "Cache not initialized"
      if ctx.options.cache
        prune_orphaned_cached_outputs(ctx, build_cache)
        build_cache.save
      end
    end
    profiler.end_phase
    result
  end

  # Delete the output of pages that vanished since the last `--cache` build.
  #
  # A cold build starts from an empty output directory, so a removed page's
  # HTML goes with it. `--cache` keeps the directory (that is the point), and
  # the render phase only ever walks pages that still exist — so the file of a
  # page that was deleted, renamed, flipped to `draft`, passed its `expires`
  # date, or turned `render = false` stayed in `public/`, kept answering 200
  # and shipped with the next `hwaro deploy`. `hwaro serve` already prunes
  # exactly this (see `stale_outputs_for_removed`); the cold `--cache` path
  # never did.
  #
  # The cache is the only record of the previous build, and it holds one entry
  # per source file with the primary output it wrote plus its `[outputs]`
  # siblings — so the entries no live page claims name the files to remove.
  # Two guards before anything is deleted:
  #
  #   * outputs the CURRENT site claims are filtered out, so a source moved
  #     onto the same URL (`foo.md` -> `foo/index.md`) can't delete the file
  #     this build just rewrote;
  #   * `delete_orphaned_outputs` refuses any path outside the output dir, so
  #     an entry left over from a build with a different `-o` is skipped
  #     rather than followed.
  #
  # Beyond the entries themselves, the source-less generated files this build
  # claimed (`Builder#claim_generated_output` — the taxonomy index/term pages,
  # their pagination pages and their feeds, and every AMP mirror) are diffed
  # against what the previous build claimed. Auto-generated OG images prune
  # themselves against their own manifest, in the generator that writes them.
  private def prune_orphaned_cached_outputs(ctx : Lifecycle::BuildContext, build_cache : Cache) : Nil
    return unless build_cache.enabled?
    output_dir = ctx.options.output_dir

    # One pass, two sets built from the SAME predicate so they cannot drift:
    # a page still writing output this build keeps its entry (`live`) and
    # protects the file it wrote (`owned`).
    live = Set(String).new
    owned = Set(String).new
    ctx.all_pages.each do |page|
      # A synthesized page has no source file and therefore no cache entry;
      # `render = false` and a URL that escapes the output dir write nothing,
      # so the file they wrote on an earlier build is stale now.
      next if page.synthesized?
      next unless page.render
      source, output = cache_paths_for(page, output_dir)
      next unless output
      live << source
      collect_page_output_paths(page, output_dir).each { |path| owned << path }
    end

    # Entries that survived but moved (a `slug`/`path`/permalink edit) leave
    # their previous file behind too; #update collected those as it went.
    stale = build_cache.prune_entries_not_in(live)
    stale.concat(build_cache.take_orphaned_outputs)
    # Everything this build still claims survives: the pages' own outputs, and
    # every file the surviving cache entries record. That second set is what
    # keeps a whole-cache invalidation — a config edit, `--full` — from
    # deleting files it only discarded the bookkeeping for, so it has to be
    # applied BEFORE the source-less lists are added.
    still_written = build_cache.current_output_files
    stale.reject! { |path| owned.includes?(path) || still_written.includes?(path) }
    stale.concat(stale_generated_outputs(build_cache, output_dir))
    stale.uniq!
    return if stale.empty?

    delete_orphaned_outputs(stale, output_dir)
  end

  # The source-less generated outputs the previous build produced and this one
  # no longer claims — a taxonomy term whose last post was deleted, and its
  # feed and pagination pages. Records this build's claims on the way out, so
  # the next build can do the same.
  #
  # Only a path a previous build actually claimed can appear here: a generator
  # that reports nothing keeps today's behaviour (its output lingers) instead
  # of having files deleted out from under it. Paths are stored relative to
  # the output directory, so a workspace that moved — or an `-o` spelled
  # absolutely one day and relatively the next — still matches.
  private def stale_generated_outputs(build_cache : Cache, output_dir : String) : Array(String)
    claimed = generated_output_claims.compact_map do |path|
      Path[path].relative_to(output_dir).to_s rescue nil
    end.sort!
    previous = build_cache.previous_generated_outputs
    build_cache.record_generated_outputs(claimed)

    return [] of String if previous.empty?
    current = claimed.to_set
    previous.reject(&.in?(current)).map { |relative| File.join(output_dir, relative) }
  end
end
