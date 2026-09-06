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
  # Output no cache entry names is still left behind: generated listings
  # (taxonomy term pages, pagination pages past the new last one), AMP mirrors,
  # auto-generated OG images and `aliases` redirect stubs. `--full` (or a build
  # without `--cache`) clears those.
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
    return if stale.empty?

    stale.reject! { |path| owned.includes?(path) }
    delete_orphaned_outputs(stale, output_dir) unless stale.empty?
  end
end
