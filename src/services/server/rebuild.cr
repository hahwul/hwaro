# Dev server — applying a ChangeSet (incremental/full rebuilds, static and content-file sync).
#
# Split out of server.cr, which keeps the require order, the Server ivars
# and the boot sequence. Parts only define or reopen types: no requires, no
# load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Server
      # Choose the cheapest rebuild strategy for a given ChangeSet and execute it.
      private def apply_changeset(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        output_dir = sanitize_output_dir(build_options.output_dir)
        strategy = effective_strategy(changeset, output_dir)
        # Recreate a vanished output root before anything writes into it.
        Hwaro::Utils::FileSafe.mkdir_p(output_dir) unless Dir.exists?(output_dir)
        # Calm watch timeline: one "↻ <what> · time" event at column 0 (the ↻
        # glyph carries "changed"), then the rebuild's own spark "rebuilt …"
        # outcome line below it. The strategy is implied by that outcome
        # (incremental N/M, re-render, full).
        timestamp = Time.local.to_s("%H:%M:%S")
        if Logger.color_enabled?
          Logger.info "\n#{Logger.glyph(:watch)} #{changeset.display}" \
                      "#{Logger.paint(" · ", Logger::Role::Dim)}#{Logger.paint(timestamp, Logger::Role::Dim)}"
        else
          Logger.info "\n~ #{timestamp}  changed  #{changeset.display}"
        end

        # Resolve removed sources to their output files BEFORE the rebuild
        # swaps in a site that no longer knows the deleted page's URL.
        stale_outputs = if changeset.removed_files.empty?
                          [] of String
                        else
                          @builder.stale_outputs_for_removed(changeset.removed_files, output_dir)
                        end

        success = case strategy
                  when :full
                    run_full_build(build_options)
                  when :templates
                    @builder.run_rerender(build_options)
                  when :incremental
                    @builder.run_incremental(changeset.modified_content, build_options)
                  when :content_and_template
                    @builder.run_incremental_then_rerender(changeset.modified_content, build_options)
                  when :static
                    copy_static(changeset, build_options)
                  when :content_files
                    copy_content_files(changeset, build_options)
                    true
                  else
                    true
                  end

        # A build can fail WITHOUT raising: pre-hook failures and phase
        # aborts (non-classified exceptions become HookResult::Abort) return
        # false. Treat that exactly like the rescue path in the caller —
        # flag it so the next changeset escalates to a full rebuild, push
        # the overlay, and skip the reload so the browser doesn't refresh
        # onto a half-built site with no visible error.
        unless success
          @rebuild_failed = true
          push_build_error("Build failed — check the terminal for details.")
          return
        end

        # Clear the failure escalation HERE, where success is actually known.
        # The watch loop must not reset it — apply_changeset returns normally
        # after a Bool-failure build too (see the `unless success` guard).
        @rebuild_failed = false

        # A config edit rebuilt the site with the new values, but [serve.*]
        # keys were consumed at startup — warn instead of silently looking
        # like they applied.
        warn_restart_only_serve_settings if changeset.config_changed

        # Copy static files if they changed alongside content/template changes
        if strategy != :static && strategy != :full && !changeset.modified_static.empty?
          unless copy_static(changeset, build_options)
            @rebuild_failed = true
            push_build_error("Build failed — check the terminal for details.")
            return
          end
        end

        # Republish non-Markdown content assets whenever they accompany any
        # rebuild that wasn't a full one. A full build already re-copies them
        # via the ReadContent → Write raw-files path; for incremental,
        # templates-only, and static-only strategies, the watcher has to do
        # it explicitly or the served bytes stay stale (issue #530).
        if strategy != :content_files && strategy != :full && !changeset.modified_content_files.empty?
          copy_content_files(changeset, build_options)
        end

        # The stale list was mapped through the PRE-rebuild site, but a
        # single changeset can delete one source and re-create the same URL
        # from another (foo.md removed + foo/index.md added). The rebuild
        # just wrote that output for the NEW owner — deleting it here would
        # 404 the page until an unrelated rebuild. Skip anything the rebuilt
        # site still claims.
        unless stale_outputs.empty?
          owned = @builder.owned_output_paths(output_dir)
          stale_outputs = stale_outputs.reject { |path| owned.includes?(path) }
        end
        remove_stale_outputs(stale_outputs, output_dir)

        @live_reload_handler.try(&.notify_reload)
      end

      # [serve.*] keys are consumed once at startup (headers baked into the
      # handler chain, fast → skip flags in the frozen watch options). A
      # config edit triggers a full rebuild that LOOKS like it applied them —
      # say so instead of leaving the user chasing a phantom.
      private def warn_restart_only_serve_settings
        current = @builder.config.try(&.serve)
        return unless current
        unless startup = @startup_serve_config
          # Initial build never loaded a config (it failed) — this rebuild's
          # values become the baseline.
          @startup_serve_config = current
          return
        end
        if startup.headers != current.headers || startup.fast != current.fast
          Logger.warn "  [serve] settings changed in config — restart `hwaro serve` to apply them."
        end
      end

      # Delete output files orphaned by removed sources, pruning any
      # directories the deletion leaves empty (e.g. `public/guide/old-page/`).
      private def remove_stale_outputs(paths : Array(String), output_dir : String)
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

      # Returns false when an escalated re-render failed (bundle fingerprint
      # moved and the page re-render below reported failure); true otherwise.
      private def copy_static(changeset : ChangeSet, build_options : Config::Options::BuildOptions) : Bool
        output_dir = sanitize_output_dir(build_options.output_dir)
        @builder.copy_changed_static(changeset.modified_static, output_dir, build_options.verbose)
        # A user's own `static/.hwaro-dev` publishes like any hidden static
        # file, so the copy above can land on top of serve's stamp. Only the
        # full-build path re-stamps, so without this the dev dir would sit
        # unmarked for the rest of the session — and `hwaro deploy` reads the
        # marker by content, so the user's bytes would not stand in for it.
        Hwaro::Utils::DevMarker.write(output_dir) unless Hwaro::Utils::DevMarker.present?(output_dir)
        # Changed image BYTES need their resized variants/LQIP regenerated
        # too — the resize hook only runs on full builds, so the copy above
        # alone left variants stale for the whole serve session (A12).
        unless build_options.skip_image_processing
          if config = @builder.config
            Hwaro::Content::Hooks::ImageHooks.reprocess_changed_images(changeset.modified_static, config, output_dir)
          end
        end
        # SCSS sources never publish verbatim — when one changed, recompile
        # the entries instead. A partial edit must rebuild every entry that
        # imports it, and there is no dependency graph, so the whole tree
        # recompiles (cheap at static-site scale). Compile errors raise and
        # reach the watcher rescue → browser overlay. The predicate is the
        # same one the copy paths use, so the gate can't drift.
        bundles_changed = false
        if (config = @builder.config) && changeset.modified_static.any? { |p| config.sass_source?(p) }
          bundles_changed = @builder.recompile_sass(output_dir)
        elsif changeset.modified_static.any? { |p| @builder.asset_bundle_source?(p) }
          # Plain (non-Sass) CSS/JS bundle sources only ever rebuilt inside
          # the full-build asset pipeline — a static-only save left the
          # fingerprinted bundle stale for the whole serve session.
          bundles_changed = @builder.reprocess_asset_bundles(output_dir)
        end

        # A changed fingerprint means every page referencing the bundle via
        # `asset()` still points at the OLD hash — rebuild so the HTML on
        # disk picks the new path up (covers the Sass path too). A full
        # rebuild, not run_rerender: templates are byte-identical here, so
        # the rerender's selective path would (correctly, by its own
        # contract) re-render nothing. Correctness over cleverness — the
        # rebuild reuses the same options the watcher's :full strategy runs.
        if bundles_changed
          Logger.info "  Asset bundle fingerprints changed — rebuilding pages to update references."
          return run_full_build(build_options)
        end
        true
      end

      private def copy_content_files(changeset : ChangeSet, build_options : Config::Options::BuildOptions)
        output_dir = sanitize_output_dir(build_options.output_dir)
        @builder.copy_changed_content_files(changeset.modified_content_files, output_dir, build_options.verbose)
        # Mirror copy_static: modified image bytes under content/ (published
        # via [content.files] or as page-bundle assets) must refresh their
        # resized variants/LQIP too (A12).
        unless build_options.skip_image_processing
          if config = @builder.config
            pages = @builder.site.try { |s| (s.pages + s.sections).as(Array(Models::Page)) }
            Hwaro::Content::Hooks::ImageHooks.reprocess_changed_images(changeset.modified_content_files, config, output_dir, pages: pages)
          end
        end
      end

      # Run a full build — the only strategy that executes `build.hooks` —
      # and record which config files those hooks rewrote without changing a
      # byte. Every full-build call site goes through here; one that didn't
      # would leave built_config_rewrite? blind to its hooks and the #760
      # loop reachable again. A build that raises still ran its pre hooks, so
      # the bookkeeping sits in an ensure.
      private def run_full_build(build_options : Config::Options::BuildOptions) : Bool
        before = config_stamps
        begin
          @builder.run(build_options)
        ensure
          note_config_rewrites(before)
        end
      end
    end
  end
end
