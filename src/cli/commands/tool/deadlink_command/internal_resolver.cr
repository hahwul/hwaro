# check-links — resolving internal links against content, generated routes and build output.
#
# Reopens `Tool::DeadlinkCommand`; deadlink_command.cr keeps the flag
# metadata, the ivars and `run`. Parts only reopen the class: no requires, no
# load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module CLI
    module Commands
      module Tool
        class DeadlinkCommand
          # Destinations the filesystem check cannot say anything about:
          # empty, protocol-relative, pure fragments, and anything carrying a
          # URI scheme (`mailto:`, `tel:`, `javascript:`, `https:`, …).
          private def skip_internal?(url : String, allow_fragment : Bool = true) : Bool
            return true if url.empty?
            return true if allow_fragment && url.starts_with?("#")
            return true if url.starts_with?("//")
            !!(url =~ /\A[a-z][a-z0-9+.\-]*:/i)
          end

          private def check_internal_links(links : Array(Link), content_dir : String, taxonomy_names : Array(String) = [] of String, base_path : String = "", language_codes : Array(String) = [] of String, generated_routes : GeneratedRoutes = GeneratedRoutes.new, oracle : Utils::BuildOutput::Oracle = Utils::BuildOutput.oracle("public", tool: "check-links")) : Array(Result)
            results = [] of Result
            project_root = Utils::PathUtils.find_project_root(content_dir)

            links.each do |link|
              decoded_url = URI.decode(link.url)
              resolved_url = decoded_url
              if resolved_url.starts_with?("/") && !base_path.empty?
                if resolved_url == base_path
                  resolved_url = "/"
                elsif resolved_url.starts_with?(base_path + "/")
                  resolved_url = resolved_url[base_path.size..]
                end
              end

              base_dir = File.dirname(link.file)

              # Resolve the URL exactly as written FIRST. A leading segment
              # that happens to match a language code may be a real section
              # (`content/ko/posts/`), and that section outranks any
              # translation reading — stripping unconditionally reported such
              # links dead even though the build publishes them.
              exists = resolves?(resolved_url, link, content_dir, base_dir, project_root, taxonomy_names, oracle) ||
                       generated_routes.matches?(resolved_url) ||
                       feed_route?(resolved_url, generated_routes, content_dir, base_dir, language_codes) ||
                       paginated_route?(resolved_url, link, content_dir, base_dir, taxonomy_names)

              # Only when the literal path fails do we read the URL as a
              # translation route (`/ko/about/` ← `content/about.ko.md`), and
              # then ONLY language-qualified evidence counts. Accepting the
              # default-language source here would pass `/ko/x/` for a site
              # that never translated `x` — a link the build emits nothing for.
              if !exists && (code = translatable_language_prefix(resolved_url, language_codes))
                stripped = resolved_url[(code.size + 1)..]
                stripped = "/" if stripped.empty?
                exists = translated_source?(stripped, code, link, content_dir, base_dir, taxonomy_names)
              end

              unless exists
                kind_label = link.kind == :image ? "Image not found" : "Internal link target not found"
                results << Result.new(link: link, status: -1, error: kind_label)
              end
            rescue ex : ArgumentError
              # A destination whose percent-encoding decodes to a byte no path
              # may contain (`/a%00b` → a real NUL) makes every `File.exists?`
              # probe in `resolves?` raise straight out of libc. Degrade PER
              # LINK — mirroring the per-file degradation `read_and_strip`
              # already does for invalid UTF-8 — so one hostile destination
              # cannot abort the whole run, hide the genuinely dead links in
              # the other files, or leave `--json` writing nothing at all to
              # stdout. The link itself is reported dead, which is exactly what
              # it is: the build cannot resolve it either.
              results << Result.new(link: link, status: -1, error: "Invalid link target: #{ex.message}")
            end
            results
          end

          # Routes the BUILD writes that have no source file to check against:
          # the sitemap, robots.txt, llms.txt, the search index and the feeds.
          #
          # Without this the checker only accepted them once `public/` existed,
          # so a `check-links` run in CI *before* `hwaro build` reported a
          # site's own `/rss.xml` and `/sitemap.xml` links dead — the exact
          # order a lint-then-build pipeline uses.
          struct GeneratedRoutes
            # Exact absolute paths (`/sitemap.xml`).
            getter paths : Set(String)
            # The feed filename, when feeds are enabled. Feeds are ALSO
            # emitted per section and per language (`/posts/rss.xml`,
            # `/ko/rss.xml`), so those are resolved by `feed_route?`, which
            # still requires the prefix to name a real section — matching the
            # bare basename anywhere would have declared `/nowhere/rss.xml`
            # live, hiding exactly the dead link this command exists to find.
            getter feed_filename : String?
            # The filename section and language feeds are written under —
            # always `rss.xml`/`atom.xml` from `[feeds] type`, regardless of
            # the root feed's `filename` or `enabled` (see `Seo::Feeds`).
            getter section_feed_filename : String?

            def initialize(@paths : Set(String) = Set(String).new, @feed_filename : String? = nil, @section_feed_filename : String? = nil)
            end

            def matches?(url : String) : Bool
              url.starts_with?("/") && paths.includes?(url)
            end
          end

          private def generated_routes(config : Models::Config?) : GeneratedRoutes
            paths = Set(String).new
            # The build always synthesizes a 404 page.
            paths << "/404.html"
            return GeneratedRoutes.new(paths) unless config

            add_route = ->(filename : String) do
              name = File.basename(filename)
              paths << "/#{name}" unless name.empty?
            end

            add_route.call(config.sitemap.filename) if config.sitemap.enabled
            add_route.call(config.robots.filename) if config.robots.enabled
            add_route.call(config.llms.filename) if config.llms.enabled
            add_route.call(config.llms.full_filename) if config.llms.enabled && config.llms.full_enabled
            add_route.call(config.search.filename) if config.search.enabled && (!config.search.sharded? || config.search.single_file)
            # Sharded index: the manifest is a fixed well-known route; the
            # per-shard files are only discoverable through it.
            paths << "/#{Content::Search::SHARDS_DIR}/#{Content::Search::MANIFEST_FILENAME}" if config.search.enabled && config.search.sharded?

            feed_filename = nil
            if config.feeds.enabled
              name = config.feeds.filename.empty? ? default_feed_filename(config.feeds.type) : File.basename(config.feeds.filename)
              unless name.empty?
                paths << "/#{name}"
                feed_filename = name
              end
            end

            GeneratedRoutes.new(paths, feed_filename, default_feed_filename(config.feeds.type))
          end

          # `/posts/rss.xml` / `/ko/rss.xml` / `/ko/posts/rss.xml` — a feed the
          # build emits beside a section or under a language prefix. The root
          # feed is already an exact path, so this only has to vouch for the
          # prefixed forms, and only when the prefix resolves to a section.
          #
          # Two different filenames are in play (see `Seo::Feeds.generate`):
          # the ROOT feed honours `[feeds] filename` and `[feeds] enabled`,
          # while section and language feeds are always written as
          # `rss.xml`/`atom.xml` (from `[feeds] type`) and a section feed is
          # gated by the section's own `generate_feeds`, not by the global
          # switch. Keying the section route on the root feed's name and
          # switch reported `/posts/rss.xml` dead on a site with `[feeds]
          # enabled = false` + `generate_feeds = true` (the build writes it)
          # and live as `/posts/feed.xml` under `filename = "feed.xml"` (the
          # build never writes it).
          private def feed_route?(url : String, routes : GeneratedRoutes, content_dir : String, base_dir : String, language_codes : Array(String)) : Bool
            return false unless url.starts_with?("/")
            basename = File.basename(url)
            if basename == routes.feed_filename
              prefix = url[0, url.size - basename.size].rstrip("/")
              return true if prefix.empty?
            end
            name = routes.section_feed_filename
            return false unless name
            return false unless basename == name

            prefix = url[0, url.size - name.size].rstrip("/")
            # `/rss.xml` at the root is only a route when the ROOT feed is
            # enabled under that name — handled above.
            return false if prefix.empty?

            segments = prefix.lstrip("/").split("/")
            if (code = segments.first?) && language_codes.includes?(code)
              segments = segments[1..]
              return true if segments.empty?
              prefix = "/#{segments.join("/")}"
            end

            return false unless index_path = section_index_path(prefix, content_dir, base_dir)
            section_generates_feeds?(File.dirname(index_path))
          end

          # A per-section feed exists only when the section opts in with
          # `generate_feeds = true` (see `Seo::Feeds`); `[feeds] sections`
          # merely filters the SITE feed's items and emits nothing per
          # section. Requiring a section index alone accepted
          # `/posts/rss.xml` on every site with a `content/posts/_index.md`
          # — a link the build never writes, waved through by the very check
          # meant to catch it. Same discipline as `paginated_route?`, which
          # reads `paginate_by` off the index before trusting `/page/N/`.
          #
          # Every `_index*` in the directory counts, not just `_index.md`:
          # a multilingual section may declare the flag only in
          # `_index.ko.md`, and `/ko/posts/rss.xml` is a real route then.
          private def section_generates_feeds?(dir : String) : Bool
            Dir.glob(File.join(dir, "_index*.{md,markdown}")).any? do |path|
              frontmatter_flag?(path, "generate_feeds")
            end
          end

          # True when a content file's front matter sets `key` to boolean
          # true, in any of the three supported front-matter formats. An
          # unreadable or malformed file reads as "not set" — the checker
          # degrades to reporting the link rather than crashing the run.
          private def frontmatter_flag?(path : String, key : String) : Bool
            content = Utils::TextUtils.strip_bom(File.read(path))
            return false unless fm = Utils::FrontmatterScanner.detect(content)
            dialect, source = fm

            case dialect
            when :toml
              return TOML.parse(source)[key]?.try(&.raw) == true
            when :yaml
              if h = YAML.parse(source).as_h?
                return h[YAML::Any.new(key)]?.try(&.raw) == true
              end
            when :json
              if h = JSON.parse(source).as_h?
                return h[key]?.try(&.raw) == true
              end
            end

            false
          rescue
            false
          end

          # Mirrors `Seo::Feeds.safe_feed_filename` for an unset filename.
          private def default_feed_filename(feed_type : String) : String
            feed_type.downcase == "atom" ? "atom.xml" : "rss.xml"
          end

          # `/posts/page/2/` — a paginated listing route. It exists only in the
          # output, so accept it when the URL minus its `/<paginate_path>/<n>/`
          # tail resolves to a section that actually paginates. The `/page/`
          # segment is trusted only for a real section, so an ordinary dead
          # `/foo/page/2/` still reports.
          private def paginated_route?(url : String, link : Link, content_dir : String, base_dir : String, taxonomy_names : Array(String)) : Bool
            return false if link.kind == :image
            match = url.match(/\A(.*)\/([^\/]+)\/(\d+)\/?\z/)
            return false unless match
            prefix = match[1]
            segment = match[2]
            prefix = "/" if prefix.empty?

            # Taxonomy term listings paginate too (`/tags/crystal/page/2/`).
            return true if segment == "page" && taxonomy_url?(prefix, taxonomy_names)

            index_path = section_index_path(prefix, content_dir, base_dir)
            return false unless index_path
            paginate_path, per_page = section_pagination(index_path)
            return false unless per_page
            return false unless segment == paginate_path

            number = match[3].to_i?
            return false unless number && number >= 1

            # Bound the page number by how many pages could possibly exist.
            # Accepting any N declared `/posts/page/99/` live on a two-page
            # section. The count is a deliberate OVER-estimate (every
            # descendant, drafts included), so the bound can never report a
            # link the build does publish.
            descendants = section_page_count(File.dirname(index_path))
            return true if descendants == 0
            number <= (descendants + per_page - 1) // per_page
          end

          # Upper bound on the pages a section can paginate: every Markdown
          # descendant that is not itself a section index.
          private def section_page_count(dir : String) : Int32
            count = 0
            Dir.glob(File.join(dir, "**", "*.{md,markdown}")) do |path|
              next if File.basename(path).starts_with?("_index.")
              count += 1
            end
            count
          end

          # Path of the `_index` file backing a section URL, if any.
          private def section_index_path(url : String, content_dir : String, base_dir : String) : String?
            base = content_target(url, content_dir, base_dir).rstrip("/")
            {"_index.md", "_index.markdown"}.each do |name|
              candidate = File.join(base, name)
              return candidate if File.exists?(candidate)
            end
            nil
          end

          # `{paginate_path, per_page}` for a section `_index` file. `per_page`
          # is nil unless the section declares a positive `paginate_by`, which
          # is what makes it produce `/page/N/` routes at all.
          private def section_pagination(index_path : String) : {String, Int32?}
            content = Utils::TextUtils.strip_bom(File.read(index_path))
            return {"page", nil} unless fm = Utils::FrontmatterScanner.detect(content)
            dialect, source = fm

            case dialect
            when :toml
              data = TOML.parse(source)
              per_page = data["paginate_by"]?.try(&.raw).as?(Int64)
              path = data["paginate_path"]?.try(&.as_s?) || "page"
              return {path, positive_page_size(per_page)}
            when :yaml
              if h = YAML.parse(source).as_h?
                per_page = h[YAML::Any.new("paginate_by")]?.try(&.as_i64?)
                path = h[YAML::Any.new("paginate_path")]?.try(&.as_s?) || "page"
                return {path, positive_page_size(per_page)}
              end
            when :json
              if h = JSON.parse(source).as_h?
                per_page = h["paginate_by"]?.try(&.as_i64?)
                path = h["paginate_path"]?.try(&.as_s?) || "page"
                return {path, positive_page_size(per_page)}
              end
            end

            {"page", nil}
          rescue
            {"page", nil}
          end

          private def positive_page_size(value : Int64?) : Int32?
            return unless value && value > 0
            value.clamp(1_i64, Int32::MAX.to_i64).to_i32
          end

          # Taxonomy listing and term pages (`/tags/`, `/categories/foo/`) are
          # generated by Hwaro at build time, so they have no source file to
          # check against. Match the URL's leading segment against the site's
          # declared taxonomy names and accept it when it lines up.
          # Language codes that get a `/<code>/` URL prefix: every declared
          # language except the default one, which is served at the root.
          private def translation_language_codes(config : Models::Config?) : Array(String)
            return [] of String unless config
            config.languages.keys.reject { |code| code.empty? || code == config.default_language }
          end

          # Returns the leading language segment of an absolute URL when it
          # names a non-default language the build can actually route, else
          # nil. The build matches filename suffixes against DECLARED codes
          # (ReadContent#extract_language_from_filename), so every declared
          # non-default code — including hyphenated ones like `pt-BR` —
          # produces `/<code>/…` routes.
          private def translatable_language_prefix(url : String, codes : Array(String)) : String?
            return if codes.empty?
            return unless url.starts_with?("/")
            segment = url.lstrip("/").split("/").first?
            return unless segment
            return unless codes.includes?(segment)
            segment
          end

          # Does `url` resolve to a source file, taxonomy route, or shipped
          # asset, read literally? This is the language-agnostic resolution the
          # checker has always performed.
          private def resolves?(url : String, link : Link, content_dir : String, base_dir : String,
                                project_root : String, taxonomy_names : Array(String),
                                oracle : Utils::BuildOutput::Oracle) : Bool
            target = content_target(url, content_dir, base_dir)
            # Most internal URLs are written with a trailing slash (`/about/`,
            # `/posts/hello/`) — strip it before computing the leaf-file
            # candidate so `target_no_slash + ".md"` resolves to
            # `content/about.md` instead of the broken `content/about/.md`.
            # The directory candidates work either way.
            target_no_slash = target.rstrip("/")

            return true if File.exists?(target) ||
                           File.exists?(target_no_slash + ".md") ||
                           File.exists?(target_no_slash + ".markdown") ||
                           File.exists?(File.join(target_no_slash, "_index.md")) ||
                           File.exists?(File.join(target_no_slash, "_index.markdown")) ||
                           File.exists?(File.join(target_no_slash, "index.md")) ||
                           File.exists?(File.join(target_no_slash, "index.markdown")) ||
                           (link.kind != :image && taxonomy_url?(url, taxonomy_names))

            # Also accept assets that live in static/ (source) or the build
            # output (after build): images under static/images/, resized/LQIP
            # variants the image pipeline emits, and anything published via
            # [content.files] or the asset pipeline. The output probe doubles
            # as the oracle for generated routes on an already-built site, and
            # follows `[build] output_dir` so a site that builds elsewhere is
            # not reported as one big pile of broken links — but only while
            # that tree is trustworthy: absent, empty and `hwaro serve` output
            # all answer false, and the run reports why (#761).
            asset_path = url.lstrip("/")
            File.exists?(File.join(project_root, "static", asset_path)) ||
              oracle.exists?(asset_path)
          end

          # Language-qualified resolution for a `/<code>/…` URL whose literal
          # path did not resolve. Deliberately narrow: only a `.<code>` source
          # or a taxonomy route counts, never the default-language file.
          private def translated_source?(url : String, code : String, link : Link,
                                         content_dir : String, base_dir : String,
                                         taxonomy_names : Array(String)) : Bool
            target_no_slash = content_target(url, content_dir, base_dir).rstrip("/")

            File.exists?("#{target_no_slash}.#{code}.md") ||
              File.exists?("#{target_no_slash}.#{code}.markdown") ||
              File.exists?(File.join(target_no_slash, "_index.#{code}.md")) ||
              File.exists?(File.join(target_no_slash, "_index.#{code}.markdown")) ||
              File.exists?(File.join(target_no_slash, "index.#{code}.md")) ||
              File.exists?(File.join(target_no_slash, "index.#{code}.markdown")) ||
              (link.kind != :image && taxonomy_url?(url, taxonomy_names))
          end

          # Map a link destination onto a path under the content directory.
          private def content_target(url : String, content_dir : String, base_dir : String) : String
            if url.starts_with?("@/")
              # Zola-style content-root link (`@/posts/hello.md`). The build
              # resolves these against the content dir, so the checker must too.
              File.join(content_dir, url[2..])
            elsif url.starts_with?("/")
              File.join(content_dir, url.lstrip("/"))
            else
              File.join(base_dir, url)
            end
          end

          private def taxonomy_url?(url : String, names : Array(String)) : Bool
            return false if names.empty?
            return false unless url.starts_with?("/")
            segments = url.lstrip("/").rstrip("/").split("/")
            return false if segments.empty? || segments.first.empty?
            names.includes?(segments.first)
          end

          private def load_config(project_root : String = ".") : Models::Config?
            config_path = File.join(project_root, "config.toml")
            return unless File.exists?(config_path)

            Dir.cd(project_root) do
              Models::Config.load
            end
          rescue Exception
            nil
          end
        end
      end
    end
  end
end
