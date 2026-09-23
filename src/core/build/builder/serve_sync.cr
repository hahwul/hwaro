# Builder — serve-mode output sync (static/content-file copies, Sass recompiles, orphaned output cleanup).
#
# Reopens `Core::Build::Builder`; builder.cr keeps the require order, the
# phase includes, every ivar and the cold-build `run`. Parts only reopen the
# class: no requires, no load-time statements
# (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Core
    module Build
      class Builder
        # Copy `src_path` onto `dest_path` atomically: copy into a
        # same-directory temp file first, then rename it into place.
        #
        # Both callers below run on the serve watcher while HTTP fibers stream
        # the very same paths to the browser, and `FileUtils.cp` opens the
        # destination with O_TRUNC and then streams — so the destination is
        # observably 0 bytes and then every intermediate size, and a request
        # landing in that window is answered with a truncated body (a 21 MB
        # stylesheet was served at 0.5 MB, header and body agreeing on the short
        # length) that nothing retries. `rename` is atomic within a filesystem,
        # so a reader sees either the old bytes or the new ones. Same invariant
        # — and the same pid+fiber temp naming, so parallel copies of sibling
        # files cannot collide — as `FileSafe.atomic_write`.
        private def atomic_copy(src_path : String, dest_path : String) : Nil
          # `FileUtils.cp` copies INTO a directory of that name; there is no
          # file to replace atomically then, so keep the old behaviour instead
          # of failing the rename on it.
          if Dir.exists?(dest_path)
            FileUtils.cp(src_path, dest_path)
            return
          end

          tmp = "#{dest_path}.#{Process.pid}.#{Fiber.current.object_id}.tmp"
          begin
            File.copy(src_path, tmp)
            File.rename(tmp, dest_path)
          rescue ex
            # Never leave the temp file behind — a failed copy must look
            # exactly like the old non-atomic failure (destination unchanged).
            File.delete(tmp) if File.exists?(tmp)
            raise ex
          end
        end

        # Copy only the specified static files to the output directory.
        # Used by serve mode when only static files have changed.
        #
        # Returns true when one of the copies landed on a file a PAGE owns
        # (`static/about/index.html` beside a page whose url is `/about/`).
        # The static-only rebuild strategy re-renders nothing, so the static
        # bytes would sit on that URL for the rest of the session; the caller
        # escalates to a full rebuild, where the render runs after the copy
        # and the page wins — exactly the cold-build outcome.
        def copy_changed_static(changed_files : Array(String), output_dir : String, verbose : Bool = false) : Bool
          static_config = static_publish_config
          config = @config
          sass_on = config.try(&.sass.enabled) || false
          copied = 0
          cwd = Dir.current
          page_outputs = owned_output_paths(output_dir).map { |path| File.expand_path(path, cwd) }.to_set
          shadowed = false
          changed_files.each do |src_path|
            # Same eligibility rule as the full build's collect_static_files
            # (phases/initialize.cr): a symlinked file whose target escapes
            # the project must not be published into the output during
            # serve either, and an unresolvable link must be a skip rather
            # than a raise — raising here escaped into the watcher loop,
            # which then failed every single iteration and could never
            # rebuild again.
            next unless publishable_static_info(src_path)

            relative = path_relative_to(src_path, "static")
            next if static_config.excluded?(relative)
            next if config.try(&.sass_source?(relative))
            # When Sass is on, a hand-written sibling of an SCSS entry must not
            # overwrite the compiled CSS during serve (full build ends with
            # SCSS winning). Skip the copy and leave the compiled output.
            if sass_on && relative.ends_with?(".css")
              scss_sibling = relative.sub(/\.css\z/i, ".scss")
              scss_src = File.join("static", scss_sibling)
              if File.exists?(scss_src) && !File.basename(scss_src).starts_with?("_")
                Logger.warn "  Sass: skipping static copy of #{relative} — sibling #{scss_sibling} compiles to the same path."
                next
              end
            end
            dest_path = File.join(output_dir, relative)
            # Parity with copy_changed_content_files: a watcher path outside
            # static/ yields a `../`-relative destination that must never be
            # written outside the output directory.
            unless Utils::OutputGuard.within_output_dir?(dest_path, output_dir)
              Logger.warn "Skipping static file outside output directory: #{relative}"
              next
            end

            Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
            atomic_copy(src_path, dest_path)
            # Recorded for the same reason the full build records its copies
            # (see Builder#note_static_copy): a later `--cache`-filtered
            # render must not skip the page whose output this just replaced.
            canonical_dest = File.expand_path(dest_path, cwd)
            note_static_copy(canonical_dest)
            shadowed ||= page_outputs.includes?(canonical_dest)
            copied += 1
          end
          Logger.outcome("copied", "#{copied} static #{copied == 1 ? "file" : "files"}") if copied > 0
          shadowed
        end

        # Recompile all SCSS entries into the output directory. Used by
        # serve mode when a `.scss` source changes — such files publish as
        # compiled `.css`, never verbatim. No-ops unless [sass] is enabled.
        #
        # Returns true when reprocessing the asset bundles changed the
        # manifest (a fingerprinted filename moved) — see
        # reprocess_asset_bundles for what callers must do then.
        def recompile_sass(output_dir : String) : Bool
          config = @config
          return false unless config && config.sass.enabled

          compiler = Assets::SassCompiler.new(config.sass, config.static)
          count = compiler.compile_all(output_dir)
          Logger.outcome("compiled", "#{count} sass #{count == 1 ? "file" : "files"}") if count > 0

          # Bundle entries with `.scss` sources only recompile inside the asset
          # pipeline (AfterInitialize on a full build). Static-only serve
          # reloads would otherwise leave fingerprinted bundles stale.
          config.assets.enabled ? reprocess_asset_bundles(output_dir) : false
        end

        # True when a watcher-relative path (e.g. "static/js/app.js") is a
        # source file of a configured [assets] bundle. The serve watcher uses
        # this to know a plain (non-Sass) static save must re-run the bundle
        # pipeline — bundle inputs are `source_dir`-joined `bundle.files`,
        # exactly how Assets::Pipeline reads them.
        def asset_bundle_source?(path : String) : Bool
          config = @config
          return false unless config && config.assets.enabled

          normalized = Path[path].normalize.to_s
          config.assets.bundles.any? do |bundle|
            bundle.files.any? do |file|
              Path[config.assets.source_dir, file].normalize.to_s == normalized
            end
          end
        end

        # Re-run the asset pipeline so SCSS (or plain CSS/JS) bundle sources
        # refresh under serve. Updates the AssetHooks class-level manifest so
        # subsequent renders see new fingerprint paths.
        #
        # Returns true when the manifest changed — with fingerprinting on,
        # every already-rendered page still references the OLD hashed
        # filename, so callers must follow up with a page re-render.
        def reprocess_asset_bundles(output_dir : String) : Bool
          config = @config
          return false unless config && config.assets.enabled

          old_manifest = Content::Hooks::AssetHooks.manifest
          pipeline = Assets::Pipeline.new(config.assets, config.base_url, config.sass.enabled)
          pipeline.process(output_dir)
          Content::Hooks::AssetHooks.replace_manifest(pipeline.manifest)
          if pipeline.manifest.size > 0
            Logger.outcome("bundled", "#{pipeline.manifest.size} asset #{pipeline.manifest.size == 1 ? "bundle" : "bundles"}")
          end
          pipeline.manifest != old_manifest
        end

        # Republish non-Markdown content assets (images, etc.) to the output
        # directory, preserving their path relative to `content/`. Mirrors what
        # the full build does via the raw-files path in the Write phase, but
        # only touches the files the watcher actually flagged as changed.
        #
        # Skips files whose extension isn't permitted by `[content.files]`, so
        # the watcher can't smuggle a `.md` or a disallowed type into output.
        # No-ops when `[content.files]` isn't enabled — nothing was published
        # in the first place, so there's nothing to refresh. (`@config` is nil
        # only before the initial build, which `Server#run_with_options`
        # already performs before spawning the watcher, so the watcher always
        # sees a loaded config.)
        def copy_changed_content_files(changed_files : Array(String), output_dir : String, verbose : Bool = false)
          config = @config
          unless config && config.content_files.enabled?
            Logger.debug "  Content-file republish skipped — content.files not enabled."
            return
          end

          copied = 0
          changed_files.each do |src_path|
            next unless File.exists?(src_path)
            next if File.directory?(src_path)

            relative = path_relative_to(src_path, "content")

            next unless config.content_files.publish?(relative)

            dest_path = File.join(output_dir, relative)
            unless Utils::OutputGuard.within_output_dir?(dest_path, output_dir)
              Logger.warn "Skipping content file outside output directory: #{relative}"
              next
            end

            Hwaro::Utils::FileSafe.mkdir_p(File.dirname(dest_path))
            atomic_copy(src_path, dest_path)
            Logger.action :copy, dest_path, Logger::Role::Dim if verbose
            copied += 1
          end
          Logger.outcome("copied", "#{copied} content #{copied == 1 ? "file" : "files"}") if copied > 0
        end

        # Map source paths that were removed from disk to the output files
        # they produced in the last build. A rebuild rewrites surviving pages
        # but never deletes what's gone, so the serve watcher captures this
        # BEFORE rebuilding (while @site still knows the page's URL/slug) and
        # removes the orphans after — otherwise a deleted page keeps serving
        # 200 and ships with the next deploy of `public/`.
        def stale_outputs_for_removed(removed_paths : Array(String), output_dir : String) : Array(String)
          outputs = [] of String
          site = @site
          removed_paths.each do |path|
            if path.starts_with?("static/")
              relative = path.lchop("static/")
              # SCSS sources publish as compiled `.css`, never verbatim — the
              # stale artifact of a removed entry is the compiled sibling.
              if @config.try(&.sass_source?(relative))
                relative = relative.sub(/\.scss\z/, ".css")
              end
              dest = File.join(output_dir, relative)
              outputs << dest if Utils::OutputGuard.within_output_dir?(dest, output_dir)
            elsif path.starts_with?("content/")
              # Same definition of "page source" the ReadContent phase and the
              # serve watcher's classify_modified use, so the three cannot
              # drift over which extensions are pages.
              if Phases::ReadContent::PAGE_EXTENSIONS.includes?(Path[path].extension.downcase)
                next unless site
                rel = path.lchop("content/")
                # Section _index pages live in site.sections, not site.pages —
                # deleting one used to leave its index.html served forever.
                if page = site.pages.find { |p| p.path == rel } || site.sections.find { |s| s.path == rel }
                  if primary = get_output_path(page, output_dir)
                    outputs << primary
                  end

                  # Sibling output-format files (see `[outputs]`): prefer what
                  # the cache actually recorded for this source (the ground
                  # truth of what was last written); fall back to recomputing
                  # from the page's effective formats when the cache has
                  # nothing (cache disabled, or never built with caching on).
                  cached_fmt_paths = @cache.try(&.output_paths_for(path)) || [] of String
                  if !cached_fmt_paths.empty?
                    outputs.concat(cached_fmt_paths)
                  elsif cfg = @config
                    outputs.concat(format_output_paths(page, output_dir, effective_output_formats(page, cfg)))
                  end
                  # Its `[amp]` mirror goes with it.
                  if (cfg = @config) && (mirror = Content::Seo::Amp.mirror_output_for(page, cfg, output_dir))
                    outputs << mirror
                  end
                end
              else
                dest = File.join(output_dir, path.lchop("content/"))
                outputs << dest if Utils::OutputGuard.within_output_dir?(dest, output_dir)
              end
            end
          end
          outputs
        end

        # Every output file the CURRENT site claims — primary page outputs
        # plus output-format siblings, computed exactly like
        # collect_page_output_paths so the two can never drift. The serve
        # watcher filters its pre-rebuild stale list through this AFTER the
        # rebuild: a source deleted and re-created under a different path in
        # one changeset (foo.md → foo/index.md) maps to the same output file,
        # which the rebuild just rewrote and must not be deleted.
        def owned_output_paths(output_dir : String) : Set(String)
          owned = Set(String).new
          if site = @site
            (site.pages + site.sections).each do |page|
              collect_page_output_paths(page, output_dir).each { |path| owned << path }
            end
          end
          owned
        end

        # Primary output file plus output-format siblings for a page — used
        # to prune the old files when an edit relocates the page's URL or
        # excludes the page from the site.
        private def collect_page_output_paths(page : Models::Page, output_dir : String) : Array(String)
          # A `render = false` page writes nothing, so it owns nothing: an
          # edit that turns rendering off must orphan the file it wrote.
          return [] of String unless page.render
          paths = [get_output_path(page, output_dir)].compact
          if cfg = @config
            paths.concat(format_output_paths(page, output_dir, effective_output_formats(page, cfg)))
            if mirror = Content::Seo::Amp.mirror_output_for(page, cfg, output_dir)
              paths << mirror
            end
          end
          paths
        end

        # Delete output files, pruning directories the deletion leaves empty.
        # Guarded so a corrupt path can never delete outside the output
        # directory, including through a symlinked parent. Serve prunes reach
        # this only through `prune_unclaimed_outputs`, which decides WHAT is
        # stale; this only does the deleting.
        private def delete_orphaned_outputs(paths : Array(String), output_dir : String)
          paths.each do |path|
            next unless Utils::OutputGuard.safe_to_delete_file?(path, output_dir)
            next unless File.exists?(path)
            File.delete(path)
            Logger.info "  Removed stale output: #{path}"

            dir = File.dirname(path)
            while Utils::OutputGuard.safe_to_delete_directory?(dir, output_dir) && Dir.exists?(dir) && Dir.empty?(dir)
              Dir.delete(dir)
              forget_created_dirs(dir)
              dir = File.dirname(dir)
            end
          rescue ex
            Logger.debug "  Could not remove stale output #{path}: #{ex.message}"
          end
        end

        # Run one taxonomy generation pass, then delete the files the previous
        # pass on this builder wrote and this one did not: a term whose last
        # post was deleted, re-tagged or drafted, with its feed and pagination
        # pages, or a whole taxonomy dropped from config.toml.
        #
        # Paths are compared relative to `output_dir`, so a pass into a
        # different output directory matches nothing and deletes nothing. A
        # file the current site renders a page to is never deleted, and
        # neither is anything when the pass raised (the previous set is kept
        # and widened, so the next complete pass still sees it).
        def track_taxonomy_outputs(output_dir : String, & : -> Array(Models::Section)) : Array(Models::Section)
          @generated_claims_mutex.synchronize { @taxonomy_pass_outputs = Set(String).new }
          begin
            sections = yield
          rescue ex
            finish_taxonomy_pass(output_dir, completed: false)
            raise ex
          end
          finish_taxonomy_pass(output_dir, completed: true)
          sections
        end

        private def finish_taxonomy_pass(output_dir : String, completed : Bool) : Nil
          written = @generated_claims_mutex.synchronize do
            current = @taxonomy_pass_outputs || Set(String).new
            @taxonomy_pass_outputs = nil
            current
          end
          relative = written.compact_map { |path| Path[path].relative_to(output_dir).to_s rescue nil }.to_set
          previous = @last_taxonomy_outputs
          unless completed
            @last_taxonomy_outputs = previous ? previous | relative : relative
            return
          end
          @last_taxonomy_outputs = relative
          prune_stale_taxonomy_outputs(previous - relative, output_dir) if previous
        end

        private def prune_stale_taxonomy_outputs(stale : Set(String), output_dir : String) : Nil
          return if stale.empty?
          prune_unclaimed_outputs(stale.map { |relative| File.join(output_dir, relative) }, output_dir)
        end

        # Delete the alias stubs and `/page/N/` files a page's previous render
        # wrote and its render in the pass that just finished did not, plus
        # every derived file of a page that is no longer in the site
        # (deleted, drafted, `render = false`). Called once a render pass is
        # complete, never per page: a stub one page dropped may be exactly
        # the file another page claims in the same pass, so nothing a live
        # page or any current stub still claims is deleted.
        def sweep_stale_derived_outputs(output_dir : String) : Nil
          site = @site
          return unless site
          live = Set(String).new
          (site.pages + site.sections).each { |page| live << page.path if page.render }

          stale = [] of String
          @page_derived_mutex.synchronize do
            pass = @derived_outputs_this_pass
            @derived_outputs_this_pass = {} of String => Array(String)
            pass.each do |page_path, derived|
              if previous = @rendered_derived_outputs[page_path]?
                stale.concat(previous - derived)
              end
              @rendered_derived_outputs[page_path] = derived
            end
            @rendered_derived_outputs.reject! do |page_path, derived|
              next false if live.includes?(page_path)
              stale.concat(derived)
              true
            end
          end
          prune_unclaimed_outputs(stale, output_dir)
        end

        # The one choke point every serve prune deletes through. `candidates`
        # are files an earlier pass wrote that the bookkeeping of THIS pass no
        # longer names; each is deleted only when nothing in the current
        # output still stands on it:
        #
        #   * a page output of the current site (`owned_output_paths`);
        #   * an alias stub / pagination page any page's render recorded;
        #   * a generated-output claim — only while the claim set is this
        #     build's own (`@generated_claims_current`): an incremental pass
        #     re-claims nothing, so there the set still names the very files
        #     being pruned;
        #   * a file this pass wrote (`written_this_build?` — every serve pass
        #     re-stamps the epoch, see `begin_serve_pass`);
        #   * a live `static/` or `content/` file that publishes at that path,
        #     which is what an incremental pass cannot learn from its claims.
        #     A static source's bytes are copied back over the stale file —
        #     it was shadowing them, and a cold build publishes them there.
        #
        # Paths are compared by a case-folded key, because the filesystem
        # deleting them may fold case (APFS, NTFS): `/Old/` → `/old/` is one
        # file there, and deleting the "old" spelling removes the new one.
        # Folding everywhere only ever keeps more.
        def prune_unclaimed_outputs(candidates : Enumerable(String), output_dir : String) : Nil
          return if candidates.empty?
          cwd = Dir.current
          keep = Set(String).new
          owned_output_paths(output_dir).each { |path| keep << output_key(path, cwd) }
          @page_derived_mutex.synchronize do
            {@rendered_derived_outputs, @derived_outputs_this_pass, @page_derived_outputs}.each do |recorded|
              recorded.each_value { |paths| paths.each { |path| keep << output_key(path, cwd) } }
            end
          end
          if @generated_claims_current
            generated_output_claims.each { |path| keep << output_key(path, cwd) }
          end

          stale = [] of String
          candidates.to_a.uniq.each do |path|
            next if keep.includes?(output_key(path, cwd)) || written_this_build?(path)
            relative = output_relative(path, output_dir, cwd)
            if relative && (source = static_source_for(relative))
              # The stale file was sitting on top of a static copy — a cold
              # build publishes the static bytes there, so put them back.
              Hwaro::Utils::FileSafe.mkdir_p(File.dirname(path))
              atomic_copy(source, path)
            elsif relative && content_source_publishes?(relative)
              # Same for a `content/` file; left as is rather than re-copied,
              # since raw files may be processed (minified) on the way out.
            else
              stale << path
            end
          end
          delete_orphaned_outputs(stale, output_dir) unless stale.empty?
        end

        # Start an incremental serve pass: stamp the epoch `written_this_build?`
        # reads, mark the claim set as a previous build's, and drop the mkdir
        # memo (see `forget_created_dirs`).
        private def begin_serve_pass : Nil
          forget_created_dirs
          mark_build_output_epoch
          @generated_claims_current = false
        end

        private def output_key(path : String, cwd : String) : String
          File.expand_path(path, cwd).downcase
        rescue ArgumentError
          path.downcase
        end

        # `path` relative to the output directory, or nil when it is outside.
        private def output_relative(path : String, output_dir : String, cwd : String) : String?
          relative = Path[File.expand_path(path, cwd)].relative_to(File.expand_path(output_dir, cwd)).to_s
          return if relative.starts_with?("..") || relative == "."
          relative
        rescue ArgumentError
          nil
        end

        # The live `static/` file that publishes verbatim at `relative`, if
        # any — same eligibility as the static copy (not excluded, not a Sass
        # source). Checked on disk, so the filesystem's own case rule applies.
        private def static_source_for(relative : String) : String?
          source = File.join("static", relative)
          return unless File.file?(source) && publishable_static_info(source)
          return if static_publish_config.excluded?(relative)
          return if @config.try(&.sass_source?(relative))
          source
        end

        # True when a non-page file under `content/` (a `[content.files]`
        # copy or a page-bundle asset) publishes at `relative`.
        private def content_source_publishes?(relative : String) : Bool
          source = File.join("content", relative)
          File.file?(source) &&
            !Phases::ReadContent::PAGE_EXTENSIONS.includes?(Path[source].extension.downcase)
        end

        # Rewrite the `[amp]` mirrors of pages an incremental strategy just
        # re-rendered. The mirror is converted from the canonical HTML, and
        # the conversion also injects `<link rel="amphtml">` into that HTML —
        # only the full build's AfterRender hook ran it, so every incremental
        # re-render dropped the link from the canonical page and left the
        # mirror serving the pre-edit content.
        private def regenerate_amp_mirrors(pages : Enumerable(Models::Page), site : Models::Site, output_dir : String, verbose : Bool) : Nil
          return unless site.config.amp.enabled
          Content::Seo::Amp.generate(pages.to_a, site.config, output_dir, verbose, builder: self)
        end

        # Resolve `path` relative to `root`, falling back to a plain prefix
        # strip when it can't be made relative (e.g. an absolute path).
        private def path_relative_to(path : String, root : String) : String
          Path[path].relative_to(root).to_s
        rescue ArgumentError
          path.lchop("#{root}/")
        end
      end
    end
  end
end
