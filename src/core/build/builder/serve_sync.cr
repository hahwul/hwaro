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
        def copy_changed_static(changed_files : Array(String), output_dir : String, verbose : Bool = false)
          static_config = static_publish_config
          config = @config
          sass_on = config.try(&.sass.enabled) || false
          copied = 0
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
            copied += 1
          end
          Logger.outcome("copied", "#{copied} static #{copied == 1 ? "file" : "files"}") if copied > 0
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
              if path.downcase.ends_with?(".md") || path.downcase.ends_with?(".markdown")
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
          paths = [get_output_path(page, output_dir)].compact
          if cfg = @config
            paths.concat(format_output_paths(page, output_dir, effective_output_formats(page, cfg)))
          end
          paths
        end

        # Delete output files an incremental rebuild has orphaned (slug
        # change, page newly excluded), pruning directories the deletion
        # leaves empty. Guarded so a corrupt path can never delete outside
        # the output directory. Mirrors Server#remove_stale_outputs.
        private def delete_orphaned_outputs(paths : Array(String), output_dir : String)
          paths.each do |path|
            next unless File.exists?(path)
            next unless Utils::OutputGuard.within_output_dir?(path, output_dir)
            File.delete(path)
            Logger.info "  Removed stale output: #{path}"

            dir = File.dirname(path)
            while dir != output_dir && Utils::OutputGuard.within_output_dir?(dir, output_dir) && Dir.exists?(dir) && Dir.empty?(dir)
              Dir.delete(dir)
              dir = File.dirname(dir)
            end
          rescue ex
            Logger.debug "  Could not remove stale output #{path}: #{ex.message}"
          end
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
