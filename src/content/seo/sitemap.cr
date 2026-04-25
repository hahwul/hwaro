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

          sitemap_pages = pages.select { |p| p.in_sitemap && p.render }

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
            Logger.warn "base_url is empty. Sitemap will contain relative URLs instead of absolute URLs."
          end

          # Pre-compute config values once outside the loop
          base = site.config.base_url.rstrip('/')
          changefreq = site.config.sitemap.changefreq
          has_changefreq = !changefreq.empty?
          escaped_changefreq = has_changefreq ? Utils::TextUtils.escape_xml(changefreq) : ""
          priority = site.config.sitemap.priority
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

              escaped_url = Utils::TextUtils.escape_xml(full_url)

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
                str << Utils::TextUtils.escape_xml(t_full)
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
          File.write(sitemap_path, xml_content)
          Logger.action :create, sitemap_path if verbose
          Logger.info "  Generated sitemap with #{sitemap_pages.size} URLs."
        end
      end
    end
  end
end
