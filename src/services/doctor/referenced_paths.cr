# Doctor — referenced files/dirs/routes and Sass source checks.
#
# Split out of doctor.cr, which keeps the require order, the Doctor ivars
# and `run`. Parts only define or reopen types: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Doctor
      # Validate that path-shaped fields in `config.toml` actually point at
      # files (or directories) that exist on disk. The build pipeline
      # doesn't fail when a referenced asset is missing — it just emits a
      # 404 in production — so a typoed `[og] default_image` would
      # otherwise only surface in the wild. Each missing path becomes a
      # `[warn]` issue under `config-path-missing` (file) or
      # `config-dir-missing` (directory), both suppressible via
      # `[doctor] ignore = [...]`. See
      # https://github.com/hahwul/hwaro/issues/489.
      # Emit a "<kind> not found" config warning for `value` unless it's blank
      # or `resolver` reports it resolves. `id`/`kind` are passed independently
      # so route checks can keep the "config-path-missing"/"file" pairing.
      private def emit_missing(issues : Array(Issue), label : String, value : String, *, resolver : String -> Bool, id : String, kind : String)
        # A value that carries its own origin (`https://cdn…/og.png`,
        # `//cdn…/og.png`, `data:…`) names something outside the project
        # tree, so "file not found" is simply the wrong answer: `[og]
        # default_image` explicitly supports absolute URLs (see
        # `OgConfig#resolve_image_url`) and doctor flagged every site using
        # a CDN. Doctor cannot validate a remote URL, so it says nothing.
        return if Content::Processors::InternalLinkResolver.has_own_origin?(value)
        stripped = strip_query_hash(value)
        return if stripped.empty?
        return if resolver.call(stripped)
        issues << Issue.new(
          id: id,
          level: :warning,
          category: "config",
          file: @config_path,
          message: "#{label}: #{value} — #{kind} not found",
        )
      end

      private def check_referenced_paths(issues : Array(Issue), config : Models::Config)
        # A prior build's output is the only evidence doctor has for a route
        # no source file explains (a pipeline-emitted asset, a generated
        # listing). Since #758 `hwaro serve` builds into `.hwaro/serve/`, so a
        # serve-only workflow leaves `output_dir` absent or frozen at an old
        # build — consult it through the oracle, which refuses a tree it may
        # not trust and explains itself instead of leaving the route reported
        # missing with no clue why (#761).
        oracle = Utils::BuildOutput.oracle(
          config.build.output_dir || "public",
          sources: [@config_path, @content_dir, @templates_dir, @static_dir, "data", "themes"],
          tool: "doctor",
        )
        unresolved_routes = 0

        emit_file = ->(label : String, value : String) do
          emit_missing(issues, label, value, resolver: ->(s : String) { path_resolves?(s) }, id: "config-path-missing", kind: "file")
        end

        emit_dir = ->(label : String, value : String) do
          emit_missing(issues, label, value, resolver: ->(s : String) { dir_resolves?(s) }, id: "config-dir-missing", kind: "directory")
        end

        # PWA offline_page / precache_urls are routes, not just static files:
        # `/about/` builds to `public/about/index.html` from `content/about.md`,
        # so resolving them against `static/` alone yields false "file not
        # found" warnings. Use a route-aware check that also accepts a matching
        # content source or a built output page.
        emit_route = ->(label : String, value : String) do
          before = issues.size
          emit_missing(issues, label, value, resolver: ->(s : String) { path_resolves?(s) || route_resolves?(s, oracle) }, id: "config-path-missing", kind: "file")
          unresolved_routes += 1 if issues.size > before
        end

        config.og.default_image.try { |v| emit_file.call("[og] default_image", v) }
        config.og.auto_image.logo.try { |v| emit_file.call("[og.auto_image] logo", v) }
        config.og.auto_image.background_image.try { |v| emit_file.call("[og.auto_image] background_image", v) }
        config.pwa.offline_page.try { |v| emit_route.call("[pwa] offline_page", v) }
        config.pwa.precache_urls.each_with_index do |url, idx|
          # External URLs aren't ours to validate; `emit_missing` drops any
          # value that carries its own origin, which also covers the
          # protocol-relative and non-http schemes the old
          # `starts_with?("http")` pair missed.
          emit_route.call("[pwa] precache_urls[#{idx}]", url)
        end
        config.pwa.icons.each_with_index do |icon, idx|
          emit_file.call("[pwa] icons[#{idx}]", icon)
        end

        # auto_includes.dirs are directory paths the build globs at runtime;
        # a missing entry produces no link tags and silently ships an
        # incomplete page.
        if config.auto_includes.enabled
          config.auto_includes.dirs.each_with_index do |dir, idx|
            emit_dir.call("[auto_includes] dirs[#{idx}]", dir)
          end
        end

        # assets pipeline only matters when enabled; bundle inputs live
        # under assets.source_dir.
        if config.assets.enabled
          source_dir = config.assets.source_dir
          emit_dir.call("[assets] source_dir", source_dir) unless source_dir.empty?

          config.assets.bundles.each_with_index do |bundle, b_idx|
            label_prefix = bundle.name.empty? ? "[[assets.bundles]][#{b_idx}]" : "[[assets.bundles]] #{bundle.name}"
            bundle.files.each_with_index do |file, f_idx|
              # Bundle file paths are resolved against assets.source_dir
              # at build time, so check there directly rather than going
              # through path_resolves?'s static/ heuristic.
              candidate = source_dir.empty? ? file : File.join(source_dir, file)
              next if File.exists?(candidate)
              issues << Issue.new(
                id: "config-path-missing",
                level: :warning,
                category: "config",
                file: @config_path,
                message: "#{label_prefix} files[#{f_idx}]: #{file} — file not found under #{source_dir.empty? ? "(repo root)" : source_dir}/",
              )
            end
          end
        end

        # One advisory for the whole run, never one per route. `hint` is nil
        # unless the tree could not be used at all (absent / serve output) or
        # was used and predates the sources; the extra condition keeps an
        # unusable tree quiet until a route actually failed because of it —
        # a site that references no pipeline-emitted path does not need to
        # hear about `public/`.
        if (hint = oracle.hint) && (oracle.usable? || unresolved_routes > 0)
          issues << Issue.new(
            id: oracle.usable? ? "build-output-stale" : "build-output-unusable",
            level: :info,
            category: "config",
            file: nil,
            message: hint,
          )
        end
      end

      # [sass] pitfalls that build and serve stay silent about: SCSS sources
      # in a directory the compiler never scans, or sources in the right
      # place with compilation left off. Both ship a site whose stylesheet
      # URLs silently 404 — worth a diagnostic here since no build phase
      # ever touches the files.
      private def check_sass(issues : Array(Issue), config : Models::Config)
        glob = File::MatchOptions.glob_default | File::MatchOptions::DotFiles

        # Zola keeps SCSS under a root `sass/` directory, so that's where
        # migrating users put it. Hwaro compiles from `static/`
        # (features/sass) and never scans `sass/`. Anchored next to
        # config.toml rather than the CWD so a doctor run pointed at
        # another project (-i / spec temp dirs) inspects that project.
        sass_dir = File.join(File.dirname(@config_path), "sass")
        if Dir.exists?(sass_dir) && Dir.glob(File.join(sass_dir, "**", "*.scss"), match: glob).any? { |p| File.file?(p) }
          issues << Issue.new(
            id: "sass-dir-not-scanned",
            level: :warning,
            category: "config",
            file: "sass/",
            message: "SCSS files found under sass/, which Hwaro never scans — SCSS sources belong under #{@static_dir}/ (e.g. #{@static_dir}/css/style.scss). Move them there (see features/sass).",
          )
        end

        # Entry files under static/ while [sass] is disabled: the raw
        # `.scss` publishes verbatim and any `<link>` to the compiled
        # `.css` 404s. Shipping raw sources can be deliberate (the bundles
        # escape hatch), so this stays advisory.
        unless config.sass.enabled
          entries = Dir.glob(File.join(@static_dir, "**", "*.scss"), match: glob)
            .select { |p| File.file?(p) && !File.basename(p).starts_with?("_") }
          unless entries.empty?
            issues << Issue.new(
              id: "sass-disabled-with-sources",
              level: :info,
              category: "config",
              file: entries.first,
              message: "#{entries.size} SCSS entry file(s) under #{@static_dir}/ but [sass] is not enabled — they publish as raw .scss. Add a [sass] section with enabled = true to compile them to .css (see features/sass).",
            )
          end
        end
      end

      # Strip query string and fragment off a config-style path so values
      # like `/images/og.png?v=2` or `/og.png#anchor` resolve against the
      # underlying file rather than failing.
      private def strip_query_hash(path : String) : String
        path.split('?', 2).first.split('#', 2).first
      end

      # Decide whether a config-shaped path string points at an existing
      # file. Authors write these in three flavors:
      # - URL-style (`/images/og.png`) → resolved against `static/`
      # - `static/foo.png` → already rooted under static/ (use as-is)
      # - `content/foo.md` or any other repo-relative path → use as-is
      private def path_resolves?(path : String) : Bool
        candidates(path).any? { |c| File.exists?(c) }
      end

      # Same lookup strategy as `path_resolves?`, but for directories.
      private def dir_resolves?(path : String) : Bool
        candidates(path).any? { |c| Dir.exists?(c) }
      end

      # Decide whether a route-shaped value (e.g. `/about/`, `/offline.html`)
      # corresponds to a page the site builds, even when no matching static
      # file exists. A route is considered valid when:
      #   - a content source exists (`content/about.md` or
      #     `content/about/index.md` for `/about/`), or
      #   - the built output page exists (`<output_dir>/about/index.html`,
      #     which follows `[build] output_dir` rather than assuming `public/`,
      #     and only when that tree is trustworthy — see `Utils::BuildOutput`).
      # This keeps doctor from flagging valid routes as "file not found" while
      # still catching genuinely-missing pages.
      private def route_resolves?(path : String, oracle : Utils::BuildOutput::Oracle) : Bool
        # Normalize to a slug: drop a leading slash, strip a trailing slash,
        # and remove a trailing `index.html` so `/about/` and
        # `/about/index.html` resolve the same way.
        slug = path.lchop("/")
        slug = slug.rchop("index.html") if slug.ends_with?("index.html")
        slug = slug.rstrip("/")

        # Content sources that would render to this route.
        content_candidates = if slug.empty?
                               ["_index.md", "_index.markdown", "index.md", "index.markdown"]
                             else
                               [
                                 "#{slug}.md",
                                 "#{slug}.markdown",
                                 File.join(slug, "index.md"),
                                 File.join(slug, "index.markdown"),
                                 File.join(slug, "_index.md"),
                                 File.join(slug, "_index.markdown"),
                               ]
                             end
        return true if content_candidates.any? { |c| File.exists?(File.join(@content_dir, c)) }

        # A prior build's output (`[build] output_dir`, "public" by default):
        # a pretty route lands
        # at `<slug>/index.html`, while an explicit file (an `.html` alias or a
        # pipeline-built asset such as `/css/app.css`) lands at the path itself.
        # The oracle answers false for a tree doctor may not trust — absent,
        # empty, or written by `hwaro serve` (#761).
        return true if oracle.exists?(File.join(slug, "index.html"))
        return true if oracle.exists?(path.lchop("/"))

        # Otherwise it's a pretty route or listing (taxonomy/section page)
        # produced at build time — doctor runs BEFORE the build (often on a clean
        # checkout) so it can't see these. Treat route-style values as valid
        # rather than false-positive; the build-time PWA precache validation is
        # authoritative for genuinely-missing entries.
        path.ends_with?("/") || File.extname(slug).empty?
      end

      private def candidates(path : String) : Array(String)
        result = [path]
        if path.starts_with?("/")
          result << File.join(@static_dir, path.lchop("/"))
        elsif !path.starts_with?("#{@static_dir}#{File::SEPARATOR}") && !path.starts_with?("#{@content_dir}#{File::SEPARATOR}")
          result << File.join(@static_dir, path)
        end
        result
      end
    end
  end
end
