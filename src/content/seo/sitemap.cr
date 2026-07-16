require "../../models/page"
require "../../models/site"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Seo
      class Sitemap
        def self.generate(pages : Array(Models::Page), site : Models::Site, output_dir : String, verbose : Bool = false, skip_if_unchanged : Bool = false)
          # Check if sitemap is enabled
          return unless site.config.sitemap.enabled

          if skip_if_unchanged && File.exists?(File.join(output_dir, site.config.sitemap.filename))
            Logger.debug "  Sitemap unchanged (cache hit), skipping."
            return
          end

          # Match feeds/llms/search behavior: drafts and preview-only
          # unpublished pages (--include-future/--include-expired) are
          # excluded from public discovery surfaces even when the build is
          # run with the corresponding include flag.
          sitemap_pages = pages.select { |p| p.in_sitemap && p.render && !p.draft && !p.unpublished }

          # Deduplicate by URL (keep last occurrence, matching build behavior)
          seen_urls = Set(String).new
          sitemap_pages = sitemap_pages.reverse.select { |p| seen_urls.add?(p.url) }.reverse!

          # Filter out excluded paths
          unless site.config.sitemap.exclude.empty?
            excluded_paths = site.config.sitemap.exclude.map do |path|
              path.starts_with?('/') ? path : "/#{path}"
            end

            sitemap_pages.reject! do |page|
              page_url = page.url.starts_with?('/') ? page.url : "/#{page.url}"
              excluded_paths.any? { |excluded| page_url == excluded || page_url.starts_with?(excluded.ends_with?("/") ? excluded : excluded + "/") }
            end
          end

          if sitemap_pages.empty?
            Logger.info "  No pages to include in sitemap."
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

          # Multilingual sites benefit from `<xhtml:link rel="alternate"
          # hreflang="...">` entries on every translated URL — Google's
          # recommended way to expose hreflang in sitemaps. Only declare
          # the namespace when we'll actually use it (#486).
          has_translations = sitemap_pages.any? { |p| !p.translations.empty? }

          xml_content = String.build(sitemap_pages.size * 256) do |str|
            str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            if has_translations
              str << "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">\n"
            else
              str << "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
            end

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
              # referencing entry).
              page.translations.each do |t|
                t_path = t.url.starts_with?('/') ? t.url : "/#{t.url}"
                t_full = base.empty? ? t_path : base + t_path
                str << "    <xhtml:link rel=\"alternate\" hreflang=\""
                str << Utils::TextUtils.escape_xml(t.code)
                str << "\" href=\""
                str << Utils::TextUtils.escape_xml(Utils::TextUtils.encode_url_path(t_full))
                str << "\" />\n"
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
            end

            str << "</urlset>\n"
          end

          filename = File.basename(site.config.sitemap.filename)
          sitemap_path = Path[output_dir, filename].to_s
          Hwaro::Utils::FileSafe.atomic_write(sitemap_path, xml_content)
          Logger.action :create, sitemap_path if verbose
          Logger.info "  Generated sitemap with #{sitemap_pages.size} URLs." if verbose
        end
      end
    end
  end
end
