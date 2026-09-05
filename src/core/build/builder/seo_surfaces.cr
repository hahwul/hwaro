# Builder — regenerating sitemap/feeds/robots/search/llms after a partial rebuild.
#
# Reopens `Core::Build::Builder`; builder.cr keeps the require order, the
# phase includes, every ivar and the cold-build `run`. Parts only reopen the
# class: no requires, no load-time statements
# (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Core
    module Build
      class Builder
        # Renderer over user feed templates (templates/rss.xml.jinja /
        # atom.xml.jinja, loaded under the keys "rss.xml"/"atom.xml"). Nil
        # when no override template exists so the feed generators keep the
        # zero-cost programmatic path. The proc renders with a FRESH Crinja
        # environment per call — the shared env is not MT-safe (with_scope
        # mutates the env) and the SEO tasks that generate feeds run in
        # parallel fibers. create_fresh_crinja_env carries the snapshot
        # template loader, so `{% include %}` inside a feed template works.
        def feed_template_renderer : Content::Seo::Feeds::Renderer?
          return unless feed_template_present?

          ->(source : String, context : Hash(String, Crinja::Value)) do
            env = create_fresh_crinja_env
            env.from_string(source).render(context)
          end
        end

        # True when a user feed template override is loaded. Also consulted
        # by the Generate phase's skip-if-unchanged gate: a template-only
        # edit doesn't touch content, so a warm --cache build would keep the
        # stale feed on disk if feeds were skipped.
        def feed_template_present? : Bool
          templates = @templates
          return false unless templates
          Content::Seo::Feeds::FEED_TEMPLATE_KEYS.values.any? { |key| templates.has_key?(key) }
        end

        # Regenerate the lightweight SEO/search surfaces (sitemap, feeds, llms,
        # search index, optionally robots) for the given page set. Each
        # generator writes a distinct output file with no shared in-process
        # state, so task order doesn't affect output.
        #
        # `raise_on_error: false`: these are the serve-time passes (watch
        # incremental, fast-start deferred). A transient generator failure
        # must warn-and-continue here — raising would skip cache.save, the
        # deferred-pages cleanup, and the live-reload signal even though
        # every page rendered fine. The cold-build Generate phase keeps the
        # fail-loud default via its own ParallelHelper.execute call.
        private def regenerate_seo_surfaces(pages : Array(Models::Page), site : Models::Site, output_dir : String, verbose : Bool, parallel : Bool, include_robots : Bool = false, options : Config::Options::BuildOptions? = nil)
          seo_tasks = [
            -> { Content::Seo::Sitemap.generate(pages, site, output_dir, verbose); nil },
            -> { Content::Seo::Feeds.generate(pages, site.config, output_dir, verbose, templates: @templates, renderer: feed_template_renderer); nil },
          ] of Proc(Nil)
          # Robots slots in right after Feeds — its original position in the
          # incremental path — so sequential (--no-parallel) output ordering is
          # preserved, not just the generated files.
          seo_tasks << -> { Content::Seo::Robots.generate(site.config, output_dir, verbose); nil } if include_robots
          seo_tasks << -> { Content::Seo::Llms.generate(site.config, pages, output_dir, verbose); nil }
          seo_tasks << -> { Content::Search.generate(pages, site.config, output_dir, verbose); nil }
          # Auto-OG images: the incremental/rerender passes never run the
          # BeforeRender `og_image:generate` hook, so a re-parsed page's
          # OG file went stale even though its HTML keeps the auto-assigned
          # URL (see ParseContent#parse_single_page). The manifest hash makes
          # this a near no-op when no title/description changed. Lazy serve
          # mode keeps its on-request contract (OgLazyImageHandler), and
          # --skip-og-image is honored like the hook does. Runs BEFORE the
          # surface pool (not inside it): generate assigns page.image, which
          # the feed/search tasks read.
          if opts = options
            ai = site.config.og.auto_image
            if ai.enabled && !opts.skip_og_image && !(ai.lazy_generate && opts.serve_mode)
              begin
                Content::Seo::OgImage.generate(pages, site.config, output_dir, verbose, parallel: false)
              rescue ex
                # Same warn-and-continue contract as the surface pool below —
                # a transient OG failure must not skip cache.save / reload.
                Logger.warn "  OG image regeneration failed: #{ex.message}"
              end
            end
          end
          ParallelHelper.execute(seo_tasks, parallel, raise_on_error: false)
          # PWA sw.js content-hashes the bytes of the files it precaches —
          # including the search index the tasks above just rewrote — so it
          # regenerates AFTER they finish, mirroring the full build's
          # AfterWrite hook. Without this no serve incremental path ever
          # rewrote sw.js and registered service workers kept serving stale
          # bytes through live reloads.
          if site.config.pwa.enabled
            begin
              Content::Seo::Pwa.generate(site, output_dir, verbose)
            rescue ex
              Logger.warn "  PWA regeneration failed: #{ex.message}"
            end
          end
        end
      end
    end
  end
end
