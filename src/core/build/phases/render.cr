# Phase: Render — template rendering (sequential/parallel/streaming)
#
# Handles the render phase: building template variables, applying Crinja
# templates to pages, shortcode processing, markdown rendering, pagination,
# and writing rendered HTML to disk. Includes caching for Crinja values
# and compiled templates to minimize allocations during parallel rendering.

require "./render/orchestration"
require "./render/fingerprints"
require "./render/output_paths"
require "./render/fanout"
require "./render/page_pipeline"
require "./render/pagination"
require "./render/html_transforms"
require "./render/template_masking"
require "./render/crinja_values"
require "./render/global_vars"
require "./render/asset_tags"
require "./render/template_variables"
require "./render/seo_vars"

module Hwaro::Core::Build::Phases::Render
  # In streaming mode, we release per-page rendered content every batch,
  # but do the more expensive Crinja cache invalidation + GC.collect
  # only every N batches. This is the main D5 tuning knob for
  # memory vs. speed on very large sites.
  private STREAMING_CLEAR_INTERVAL = 4

  # Auto render-worker thresholds.
  #
  # What actually caps useful render parallelism is not the CPU count but how
  # many page objects a single page render materializes from a site-wide
  # collection: every `{% for p in site.pages %}` / `section.pages` iteration
  # allocates a Crinja::Value per item, and past a small worker count Boehm's
  # global allocation lock serializes that fan-out while the extra fibers add
  # pure contention. Measured on an M4 Max (14 cores), release binaries,
  # min-of-N, output verified byte-identical at every worker count:
  #
  #   corpus (5000 pages)         fan-out/page   j1      j2      j4      j8
  #   harsh (site.pages loop)          5625    18.4s   26.0s   42.8s   50.1s
  #   harsh minus site.pages            625     3.02s   2.80s   4.23s   5.17s
  #   public (ssg-benchmark)              0     1.45s   1.00s   0.73s   0.91s
  #
  # The curves invert, so no single constant wins: the old `cpu_count * 2`
  # default (28 fibers) cost 2.4x on the first corpus and 2.2x on the third.
  # Syntax highlighting was measured and ruled out as a factor (the same
  # corpora with `--skip-highlighting` are within noise of the rows above).
  # The low-fan-out ceiling is 4 rather than the core count: sweeping 3-6 on
  # every low-fan-out corpus (docs, public at 50/500/5000 pages, 9-12 timed
  # runs each, interleaved) put 4 first or within 2% of first on all of them,
  # while 6 cost 3% on docs and 5000-page public alike.
  private RENDER_FANOUT_SERIAL    = 500 # >= this many items/page -> 1 worker
  private RENDER_FANOUT_LIMITED   = 100 # >= this many items/page -> 2 workers
  private RENDER_WORKERS_AUTO_CAP =   4 # ceiling for low-fan-out sites
  private RENDER_WORKERS_UNKNOWN  =   2 # templates unanalyzable -> hedge
  # Below this share of analyzed pages the mean is not representative of the
  # render, so the hedge is used instead of a fan-out that ignored most pages.
  private RENDER_FANOUT_MIN_KNOWN_RATIO = 0.5
end
