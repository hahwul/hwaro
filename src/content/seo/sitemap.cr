require "../../models/page"
require "../discovery_pages"
require "../../models/site"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Seo
      class Sitemap
        # The file the current config publishes (none when disabled) — what
        # the builder claims whether `generate` wrote it or skipped it as
        # unchanged, so a warm `--cache` build or a serve rebuild removes a
        # sitemap an earlier config published (disabled, or renamed).
        #
        # A sitemap too large for one file is an index plus the parts it
        # lists; those are read back from the index on disk, so a skipped
        # (unchanged) sitemap claims them too.
        def self.published_outputs(config : Models::Config, output_dir : String) : Array(String)
          return [] of String unless config.sitemap.enabled
          filename = File.basename(config.sitemap.filename)
          main = Path[output_dir, filename].to_s
          [main] + (1..listed_part_count(main)).map { |i| Path[output_dir, part_name(filename, i)].to_s }
        end

        # The sitemap protocol's per-file limits: 50,000 URLs and 50 MB
        # (52,428,800 bytes) uncompressed. Search engines reject a larger
        # file outright.
        MAX_URLS  =     50_000
        MAX_BYTES = 52_428_800

        INDEX_HEADER = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" \
                       "<sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"

        # `sitemap.xml` → `sitemap-1.xml`, `sitemap-2.xml`, …
        def self.part_name(filename : String, index : Int32) : String
          ext = File.extname(filename)
          "#{filename.rchop(ext)}-#{index}#{ext}"
        end

        # How many parts the sitemap index at `path` lists (0 when the file
        # is missing or a plain urlset). Only a file that starts with the
        # index header this generator writes counts, so a user's own file is
        # never taken for one.
        private def self.listed_part_count(path : String) : Int32
          head = File.open(path) { |f| f.read_string(Math.min(f.size, INDEX_HEADER.bytesize.to_i64).to_i) }
          return 0 unless head == INDEX_HEADER
          File.read(path).scan("<sitemap>").size
        rescue IO::Error
          0
        end

        def self.generate(pages : Array(Models::Page), site : Models::Site, output_dir : String, verbose : Bool = false, skip_if_unchanged : Bool = false)
          # Check if sitemap is enabled
          return unless site.config.sitemap.enabled

          # `File.basename` here too — the write below basenames the configured
          # filename, so probing the raw value made the cache-hit check look for
          # a path that is never written and re-emit the sitemap every build.
          if skip_if_unchanged && File.exists?(File.join(output_dir, File.basename(site.config.sitemap.filename)))
            Logger.debug "  Sitemap unchanged (cache hit), skipping."
            return
          end

          # Match feeds/llms/search behavior: drafts and preview-only
          # unpublished pages (--include-future/--include-expired) are
          # excluded from public discovery surfaces even when the build is
          # run with the corresponding include flag.
          # `output_suppressed` too: a page the render phase declined to write
          # because another page owns its output file must not be advertised
          # as a URL — on a case-folding host it is a guaranteed 404. And a
          # `redirect_to` stub declares its target as canonical, so listing
          # it is a "page with redirect" sitemap error.
          sitemap_pages = pages.select { |p| p.in_sitemap && p.published_content? }
          # `[versions] search` governs the sitemap too: older versions are
          # advertised only when it is "all" (same switch as search.json).
          versions = site.config.versions
          sitemap_pages.select! { |p| versions.in_search?(p) } if versions.enabled?

          sitemap_pages = DiscoveryPages.dedupe_by_url(sitemap_pages)
          DiscoveryPages.reject_excluded!(sitemap_pages, site.config.sitemap.exclude)

          if sitemap_pages.empty?
            # Still (re)write the file: returning here left a PREVIOUS
            # build's sitemap on disk when the last eligible page was
            # drafted/excluded — stale URLs kept being served and deployed.
            # An empty urlset is valid per the sitemap protocol.
            Logger.info "  No pages to include in sitemap — writing an empty sitemap."
            empty_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" \
                        "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n" \
                        "</urlset>\n"
            write_files(output_dir, File.basename(site.config.sitemap.filename), [empty_xml], "", verbose)
            return
          end

          if site.config.base_url.empty?
            Logger.warn "base_url is empty. Sitemap, feeds, robots.txt, and SEO/social (canonical, og:url) URLs will use relative (or omitted) URLs instead of absolute ones. Set base_url for production deploys."
          end

          # Pre-compute config values once outside the loop
          base = site.config.base_url.rstrip('/')
          changefreq = site.config.sitemap.changefreq
          has_changefreq = !changefreq.empty?
          escaped_changefreq = has_changefreq ? Utils::TextUtils.escape_xml(changefreq) : ""
          # Clamp to the sitemap protocol's [0.0, 1.0] at the emit site so an
          # out-of-range configured value can't produce an invalid sitemap. The
          # loaded config value is left raw on purpose so `hwaro doctor` can still
          # detect and warn about the misconfiguration (and offer to fix it).
          priority = site.config.sitemap.priority.clamp(0.0, 1.0)
          priority_str = "    <priority>#{priority}</priority>\n"

          # A translation link whose target page is never written (render =
          # false, or a draft/preview-only unpublished page) would advertise
          # a 404 to crawlers, and one that is a `redirect_to` stub points at
          # a non-canonical bounce page. Build the set of URLs published as
          # content (same eligibility the <loc> entries use, minus in_sitemap
          # — an in_sitemap=false page is still written and is a valid
          # alternate) and filter hreflang alternates through it.
          written_urls = Set(String).new
          pages.each do |p|
            written_urls << p.url if p.published_content?
          end

          # Multilingual sites benefit from `<xhtml:link rel="alternate"
          # hreflang="...">` entries on every translated URL — Google's
          # recommended way to expose hreflang in sitemaps. Only declare
          # the namespace when we'll actually use it (#486).
          has_translations = sitemap_pages.any? { |p| p.translations.any? { |t| written_urls.includes?(t.url) } }

          header = String.build do |str|
            str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            if has_translations
              str << "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">\n"
            else
              str << "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
            end
          end
          footer = "</urlset>\n"

          # Every `<url>` entry, back to back; entry i ends at byte `ends[i]`.
          ends = [] of Int32
          entries = String.build(sitemap_pages.size * 256) do |str|
            sitemap_pages.each do |page|
              path = page.url.starts_with?('/') ? page.url : "/#{page.url}"
              full_url = base.empty? ? path : base + path

              # Percent-encode before XML-escaping: the sitemap protocol
              # requires RFC 3986 URIs, so non-ASCII paths must be escaped.
              escaped_url = Utils::TextUtils.escape_xml(Utils::TextUtils.encode_url_path(full_url))

              str << "  <url>\n"
              str << "    <loc>#{escaped_url}</loc>\n"

              # Hreflang alternates — emit one per translation (including
              # the current page itself; Google's spec asks for a self-
              # referencing entry), then `x-default` for the
              # default-language version, matching `hreflang_tags`.
              default_href = nil
              page.translations.each do |t|
                next unless written_urls.includes?(t.url)
                t_path = t.url.starts_with?('/') ? t.url : "/#{t.url}"
                t_full = base.empty? ? t_path : base + t_path
                href = Utils::TextUtils.escape_xml(Utils::TextUtils.encode_url_path(t_full))
                default_href = href if t.is_default
                str << "    <xhtml:link rel=\"alternate\" hreflang=\""
                str << Utils::TextUtils.escape_xml(t.code)
                str << "\" href=\"" << href << "\" />\n"
              end
              if default_href
                str << "    <xhtml:link rel=\"alternate\" hreflang=\"x-default\" href=\"" << default_href << "\" />\n"
              end

              # Add lastmod if available
              if date = (page.updated || page.date)
                str << "    <lastmod>#{date.to_s("%Y-%m-%d")}</lastmod>\n"
              end

              if has_changefreq
                str << "    <changefreq>#{escaped_changefreq}</changefreq>\n"
              end

              str << priority_str

              str << "  </url>\n"
              ends << str.bytesize
            end
          end

          parts = split(ends, header.bytesize + footer.bytesize).map { |(from, to)| "#{header}#{entries.byte_slice(from, to - from)}#{footer}" }
          write_files(output_dir, File.basename(site.config.sitemap.filename), parts, base, verbose)
          Logger.info "  Generated sitemap with #{sitemap_pages.size} URLs#{parts.size > 1 ? " in #{parts.size} files" : ""}." if verbose
        end

        # Byte ranges of the entries (entry i ends at byte `ends[i]`), one per
        # file: each holds at most MAX_URLS entries and, with `overhead` bytes
        # of header and footer, at most MAX_BYTES (an entry larger than that
        # on its own still gets a file). One range, the whole sitemap, when
        # everything fits.
        def self.split(ends : Array(Int32), overhead : Int32) : Array({Int32, Int32})
          ranges = [] of {Int32, Int32}
          from = 0
          count = 0
          ends.each_with_index do |stop, i|
            start = i == 0 ? 0 : ends[i - 1]
            if count > 0 && (count == MAX_URLS || overhead + stop - from > MAX_BYTES)
              ranges << {from, start}
              from = start
              count = 0
            end
            count += 1
          end
          ranges << {from, ends.last? || 0}
          ranges
        end

        # Write `parts.first` as `filename` when there is one part; otherwise
        # write the parts as `filename-N` and `filename` as the index listing
        # them. Parts an earlier, larger sitemap listed that this one does
        # not need are removed, so a site that shrinks back under the limit
        # stops publishing them.
        private def self.write_files(output_dir : String, filename : String, parts : Array(String), base : String, verbose : Bool) : Nil
          main = Path[output_dir, filename].to_s
          previous = listed_part_count(main)
          files = parts.size == 1 ? [] of String : parts
          files.each_with_index do |xml, i|
            path = Path[output_dir, part_name(filename, i + 1)].to_s
            Hwaro::Utils::FileSafe.atomic_write(path, xml)
            Logger.action :create, path if verbose
          end
          content = parts.first
          unless files.empty?
            content = String.build do |str|
              str << INDEX_HEADER
              files.size.times do |i|
                loc = Utils::TextUtils.escape_xml(Utils::TextUtils.encode_url_path("#{base}/#{part_name(filename, i + 1)}"))
                str << "  <sitemap>\n    <loc>" << loc << "</loc>\n  </sitemap>\n"
              end
              str << "</sitemapindex>\n"
            end
          end
          Hwaro::Utils::FileSafe.atomic_write(main, content)
          Logger.action :create, main if verbose
          (files.size + 1..previous).each do |i|
            path = Path[output_dir, part_name(filename, i)].to_s
            File.delete(path) if File.file?(path)
          end
        end
      end
    end
  end
end
