# Builder — the URL plan behind `hwaro tool urls`.
#
# Reopens `Builder`; required from ../builder.cr. Parts only reopen the
# class: no requires, no load-time statements, no ivar declarations
# (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Core
    module Build
      class Builder
        # One URL a build publishes. `kind` is "page", "section", "alias",
        # "pagination", "taxonomy", "term" or "feed"; `source` is the content
        # file behind it, nil for a URL no authored file owns (taxonomy
        # pages, feeds, `[[content.generate]]` pages).
        record PlannedUrl, url : String, kind : String, source : String?

        # The URLs `run(options)` would publish, in write order, with no
        # template rendered, nothing written and no network request.
        #
        # Runs the build's own ReadContent, ParseContent and Transform phases
        # (publish filters, cascade, permalinks, languages, versions,
        # `[[content.generate]]`), then asks the writers' own planners what
        # they would write: `compute_output_url_winners` (collisions),
        # `each_alias_output`, `section_pagination`,
        # `Taxonomies.planned_urls` and `Feeds.published_outputs`. A second
        # copy of any of those rules would be a preview that drifts from the
        # site.
        #
        # Not run: `[build] hooks`, `[[data.remote]]` fetches (a tool never
        # touches the network; a `[[content.generate]]` rule over a remote
        # key is skipped with a warning, as `tool list` skips it), the lifecycle hooks (none touches the
        # page set before Render) and everything from Render on. Not listed:
        # files that are not routes of their own — static and bundle files,
        # sitemap/robots/llms/search index, `[outputs]` formats, AMP mirrors.
        def plan_urls(options : Config::Options::BuildOptions) : Array(PlannedUrl)
          config = Models::Config.load(env: options.env)
          @config = config
          options.apply_build_config!(config.build)
          output_dir = options.output_dir

          ctx = Lifecycle::BuildContext.new(options)
          ctx.builder = self
          @context = ctx
          profiler = Profiler.new(enabled: false)

          # The side-effect-free part of the Initialize phase: no output
          # directory, no static copy, no cache file.
          @cache = Cache.new(enabled: false, cache_path: Cache.path_for(false))
          @output_cwd = Dir.current
          site = Models::Site.new(config)
          @site = site
          # `[[content.generate]]` plans pages from the data tree (the
          # disk half of `load_data_files`), and `[git] use_date` dates feed
          # `[permalinks]` tokens.
          DataDisk.load_tree.children.each { |key, child| site.data[key] = DataDisk.tree_to_crinja(child) }
          remote_keys = config.data_remote.map(&.key.downcase)
          config.content_generate.reject! do |rule|
            root_key = rule.source.split('.').first
            next false unless remote_keys.includes?(root_key.downcase)
            Logger.warn "[[content.generate]] \"#{rule.source}\": remote source — its pages are not listed (a build fetches site.data.#{root_key}; `tool urls` does not)."
            true
          end
          collect_git_info(config)
          ctx.site = site
          ctx.config = config

          phases = [
            -> { execute_read_content_phase(ctx, profiler) },
            -> { execute_parse_content_phase(ctx, profiler) },
            -> { execute_transform_phase(ctx, profiler) },
          ]
          phases.each do |phase|
            next if phase.call == Lifecycle::HookResult::Continue
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_INTERNAL,
              message: "Could not plan the site's URLs — see the log above for the failing phase.",
            )
          end

          # Loaded only now: with templates in hand the parse phase renders
          # every page summary. The pagination gate below needs their names.
          templates = load_templates
          ctx.templates = templates

          all_pages = ctx.all_pages
          @output_url_winners = compute_output_url_winners(all_pages)

          planned = [] of PlannedUrl
          output_writers(all_pages).each do |page|
            source = page.synthesized? ? nil : File.join("content", page.path)
            plan_page(page, site, templates, output_dir, source, planned)
            each_alias_output(page, output_dir) { |url, dest| planned << PlannedUrl.new(alias_stub_url(url, dest, output_dir), "alias", source) }
          end

          taxonomy = Content::Taxonomies.planned_urls(site, output_dir)
          taxonomy.each { |entry| planned << PlannedUrl.new(entry.url, entry.kind, nil) }
          plan_term_aliases(site, taxonomy, output_dir, planned)

          Content::Seo::Feeds.published_outputs(all_pages, config, output_dir).each do |path|
            next unless file = Utils::PathUtils.relative_path(path, output_dir)
            planned << PlannedUrl.new(output_file_url(file), "feed", nil)
          end

          # A later writer replaces an earlier one's file (a taxonomy page
          # over the content page at its URL): one row per URL, the last
          # writer's.
          by_url = {} of String => PlannedUrl
          planned.each { |entry| by_url[entry.url] = entry }
          by_url.values
        end

        # `page`'s own URL and, for a paginated section, its pager pages —
        # the gates of `write_output` and `write_paginated_output`.
        private def plan_page(page : Models::Page, site : Models::Site, templates : Hash(String, String), output_dir : String, source : String?, planned : Array(PlannedUrl)) : Nil
          return if collision_suppressed?(page, page.url)
          unless get_output_path(page, output_dir)
            warn_unpublishable(page)
            return
          end
          url = page.url.starts_with?('/') ? page.url : "/#{page.url}"
          planned << PlannedUrl.new(url, page.is_a?(Models::Section) ? "section" : "page", source)

          return unless page.is_a?(Models::Section) && paginated_section?(page, determine_template(page, templates, site))
          section_pagination(page, site).paginated_pages.each do |paginated|
            number = paginated.page_number
            next if number == 1 || paginated_output_path(page, number, output_dir, page.paginate_path).nil?
            planned << PlannedUrl.new("#{url.rstrip('/')}/#{page.paginate_path}/#{number}/", "pagination", source)
          end
        end

        # The redirect stubs of the term `_index.md` files whose term page is
        # written (`Taxonomies.render_taxonomy_term` → `write_term_aliases`).
        private def plan_term_aliases(site : Models::Site, taxonomy : Array(Content::Taxonomies::PlannedUrl), output_dir : String, planned : Array(PlannedUrl)) : Nil
          term_meta = site.sections.select(&.term_metadata).index_by(&.url)
          return if term_meta.empty?
          term_urls = taxonomy.select { |entry| entry.kind == "term" }.map(&.url).to_set
          taxonomy_urls = taxonomy.select(&.kind.in?("taxonomy", "term")).map(&.url).to_set
          term_meta.each do |url, meta|
            next unless term_urls.includes?(url)
            each_alias_output(meta, output_dir, term_alias_refusals(meta, taxonomy_urls)) do |alias_url, dest|
              planned << PlannedUrl.new(alias_stub_url(alias_url, dest, output_dir), "alias", File.join("content", meta.path))
            end
          end
        end

        # The URL a redirect stub answers at. `url` (`normalize_alias_url`)
        # is the alias as a collision key, which spells `/x/index.htm` and
        # `/o.html/` as directories; the stubs written for them are the files
        # `x/index.htm` and `o.html`, and a host serves those names.
        private def alias_stub_url(url : String, dest : String, output_dir : String) : String
          return url unless url.ends_with?('/') && (file = Utils::PathUtils.relative_path(dest, output_dir))
          natural = Utils::PathUtils.output_file_key(url).try { |dir| Path.posix(dir, "index.html").to_s }
          file == natural ? url : output_file_url(file)
        end

        # The URL that serves an output file given relative to the output
        # directory: `posts/a/index.html` is `/posts/a/`, `old.html` and
        # `rss.xml` are themselves. The characters of a file name that a URL
        # cannot hold raw are escaped as `Page#url=` escapes them.
        private def output_file_url(file : String) : String
          url = "/#{file.gsub('\\', '/').gsub('%', "%25").gsub(Models::Page::URL_DELIMITER_ESCAPES)}"
          url.ends_with?("/index.html") ? url.rchop("index.html") : url
        end
      end
    end
  end
end
