require "file_utils"
require "html"
require "../../models/config"
require "../../models/page"
require "../../models/section"
require "../../utils/logger"
require "../../utils/text_utils"
require "../../utils/sort_utils"
require "../processors/markdown"
require "../processors/internal_link_resolver"

module Hwaro
  module Content
    module Seo
      class Feeds
        def self.generate(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false, skip_if_unchanged : Bool = false)
          if skip_if_unchanged && config.feeds.enabled
            feed_file = config.feeds.filename.empty? ? (config.feeds.type == "atom" ? "atom.xml" : "rss.xml") : config.feeds.filename
            if File.exists?(File.join(output_dir, feed_file))
              Logger.debug "  Feeds unchanged (cache hit), skipping."
              return
            end
          end

          # 1. Generate Main Site Feed
          if config.feeds.enabled
            site_pages = pages.reject { |p| p.draft || !p.render || p.is_a?(Models::Section) }

            # Deduplicate by URL (keep last occurrence, matching build behavior)
            seen_urls = Set(String).new
            site_pages = site_pages.reverse.select { |p| seen_urls.add?(p.url) }.reverse!

            # Filter by section if configured for main feed
            if !config.feeds.sections.empty?
              site_pages = site_pages.select { |p|
                config.feeds.sections.any? { |s| p.section == s || p.section.starts_with?("#{s}/") }
              }
            end

            # When multilingual and default_language_only is true,
            # the main feed only contains default language pages.
            # When false, the main feed includes all languages (original behavior).
            if config.multilingual? && config.feeds.default_language_only
              default_lang = config.default_language
              site_pages = site_pages.select { |p|
                lang = p.language || default_lang
                lang == default_lang
              }
            end

            process_feed(site_pages, config, output_dir, config.feeds.filename, config.title, "", verbose)
          end

          # 2. Generate Section Feeds — pre-group pages by section for O(1) lookup
          pages_by_section = {} of String => Array(Models::Page)
          pages.each do |p|
            next if p.draft || !p.render || p.is_a?(Models::Section)
            (pages_by_section[p.section] ||= [] of Models::Page) << p
          end

          pages.each do |page|
            # Check if it's a section and has feed generation enabled
            if page.is_a?(Models::Section) && page.generate_feeds && page.render && !page.draft
              section_pages = pages_by_section[page.section]? || [] of Models::Page

              # Construct output path for section feed
              # e.g., output_dir/posts/rss.xml
              section_output_dir = File.join(output_dir, page.url.lchop("/"))
              Hwaro::Utils::FileSafe.mkdir_p(section_output_dir)

              feed_title = "#{config.title} - #{page.title}"

              process_feed(section_pages, config, section_output_dir, "", feed_title, page.url, verbose)
            end
          end

          # 3. Generate Language-specific Feeds (for non-default languages)
          if config.multilingual?
            generate_language_feeds(pages, config, output_dir, verbose)
          end
        end

        # Generate per-language feeds for non-default languages.
        # Each language with generate_feed=true gets its own feed at /{lang}/rss.xml (or atom.xml).
        private def self.generate_language_feeds(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false)
          default_lang = config.default_language

          config.languages.each do |lang_code, lang_config|
            # Skip the default language — it's already covered by the main feed
            next if lang_code == default_lang

            # Respect per-language generate_feed setting
            next unless lang_config.generate_feed

            # Filter pages for this language (single pass)
            lang_pages = pages.select { |p|
              !p.draft && p.render && !p.is_a?(Models::Section) && p.language == lang_code
            }

            # Apply section filter if configured on the main feed
            if !config.feeds.sections.empty?
              lang_pages.select! { |p|
                config.feeds.sections.any? { |s| p.section == s || p.section.starts_with?("#{s}/") }
              }
            end

            # Don't emit a feed for a language with no content — its channel
            # <link> would point at a non-existent /{lang}/ home (404).
            next if lang_pages.empty?

            # Build the output directory: output_dir/{lang}/
            lang_output_dir = File.join(output_dir, lang_code)
            Hwaro::Utils::FileSafe.mkdir_p(lang_output_dir)

            # Build a language-specific feed title
            lang_name = lang_config.language_name
            feed_title = "#{config.title} (#{lang_name})"

            # base_path corresponds to the URL prefix for this language feed
            # e.g., "/ko/" so the self-referencing link becomes base_url/ko/rss.xml
            base_path = "/#{lang_code}/"

            process_feed(lang_pages, config, lang_output_dir, "", feed_title, base_path, verbose, lang_code)
          end
        end

        def self.process_feed(
          pages : Array(Models::Page),
          config : Models::Config,
          output_dir : String,
          custom_filename : String,
          feed_title : String,
          base_path : String = "",
          verbose : Bool = false,
          language : String? = nil,
        )
          # Determine feed type and filename
          feed_type = config.feeds.type.downcase
          unless ["rss", "atom"].includes?(feed_type)
            feed_type = "rss"
          end

          filename = if !custom_filename.empty?
                       custom_filename
                     else
                       feed_type == "atom" ? "atom.xml" : "rss.xml"
                     end

          # Sort a copy to avoid mutating the caller's array
          pages = pages.sort { |a, b| Utils::SortUtils.compare_by_date(a, b) }

          # Apply limit
          if config.feeds.limit > 0
            pages = pages.first(config.feeds.limit)
          end

          # Determine whether feed content will be plain text or HTML.
          # get_content_for_feed returns plain text when:
          # - full_content is false (uses description or 300-char summary)
          # - truncate > 0 (strips HTML and truncates)
          is_text = !config.feeds.full_content || config.feeds.truncate > 0

          # Generate feed content
          feed_content = case feed_type
                         when "atom"
                           generate_atom(pages, config, filename, is_text, feed_title, base_path, language)
                         else
                           generate_rss(pages, config, filename, is_text, feed_title, base_path, language)
                         end

          # Write feed file (basename prevents path traversal via config filename)
          feed_path = File.join(output_dir, File.basename(filename))
          File.write(feed_path, feed_content)
          Logger.action :create, feed_path if verbose
        end

        # Build the self-referencing feed URL from config, base path, and filename.
        private def self.build_feed_url(config : Models::Config, base_path : String, filename : String) : {String, String}
          base_url = config.base_url.rstrip('/')
          feed_url_path = base_path.empty? ? filename : File.join(base_path, filename)
          # RSS/Atom require RFC 3986 URIs — percent-encode non-ASCII paths
          # (e.g. a taxonomy term feed under `/tags/한국어/`).
          feed_url = Utils::TextUtils.encode_url_path("#{base_url}/#{feed_url_path.lchop("/")}")
          {base_url, feed_url}
        end

        # The canonical HTML URL the feed represents — the site root for the
        # main feed, the section page for a section feed, or the language home
        # for a per-language feed (base_path is "/ko/" etc.). Used for the RSS
        # channel/Atom alternate <link> and as the Atom <id>, so every feed
        # points at the right page and carries a unique IRI (RFC 4287).
        private def self.feed_home_url(config : Models::Config, base_path : String) : String
          base_url = config.base_url.rstrip('/')
          # End with "/" so the channel <link> / Atom <id> match the homepage
          # canonical (base_url + "/") and the per-language branch below. When
          # base_url is empty this yields "/" rather than an empty (invalid)
          # <link> element.
          return "#{base_url}/" if base_path.empty?
          Utils::TextUtils.encode_url_path("#{base_url}/#{base_path.strip("/")}/")
        end

        # Absolutize feed-body links so RSS <content:encoded> / Atom <content>
        # render correctly in readers (which consume the HTML out of the page's
        # URL context). Falls back to the subpath-prefix pass when base_url is
        # empty (no host to absolutize against).
        private def self.absolutize_feed_html(html : String, page : Models::Page, config : Models::Config) : String
          base_url = config.base_url.rstrip('/')
          if base_url.empty?
            Processors::InternalLinkResolver.prefix_root_relative_links(html, config.base_url)
          else
            Processors::InternalLinkResolver.absolutize_links(html, page_full_url(page, base_url))
          end
        end

        # Build the full absolute URL for a page.
        private def self.page_full_url(page : Models::Page, base_url : String) : String
          path = page.url.starts_with?('/') ? page.url : "/#{page.url}"
          Utils::TextUtils.encode_url_path(base_url.empty? ? path : base_url + path)
        end

        # Convert a feed timestamp to UTC, but re-anchor "midnight in a non-UTC
        # zone" to UTC of the same wall-clock date. Date-only TOML/YAML values
        # (e.g. `date = 2026-03-05`) are parsed as local midnight; a naive
        # `.to_utc` on a `+09:00` host pushes the calendar date back a day
        # (`2026-03-04T15:00:00Z`). Both RSS `<pubDate>` and Atom `<updated>`
        # route through here so the two feeds report the same calendar date.
        private def self.normalize_feed_time(time : Time) : Time
          if time.location != Time::Location::UTC &&
             time.hour == 0 && time.minute == 0 &&
             time.second == 0 && time.nanosecond == 0
            Time.utc(time.year, time.month, time.day)
          else
            time.to_utc
          end
        end

        # Format a Time as an RFC 822/2822 datetime suitable for RSS `<pubDate>`.
        # `Time#to_rfc2822` omits the leading zero on day-of-month, which some
        # readers reject; force `two_digit_day: true`.
        private def self.format_rfc822(time : Time) : String
          normalized = normalize_feed_time(time)
          String.build do |io|
            formatter = Time::Format::Formatter.new(normalized, io)
            formatter.rfc_2822(time_zone_gmt: false, two_digit_day: true)
          end
        end

        def self.generate_rss(
          pages : Array(Models::Page),
          config : Models::Config,
          filename : String,
          is_text : Bool,
          feed_title : String,
          base_path : String,
          language : String? = nil,
        ) : String
          base_url, feed_url = build_feed_url(config, base_path, filename)
          full_content = config.feeds.full_content

          String.build(500 + pages.size * 300) do |str|
            str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            # Declare the `content:` namespace so we can emit
            # <content:encoded> alongside the summary <description>
            # (gh#526).
            str << "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\" xmlns:content=\"http://purl.org/rss/1.0/modules/content/\">\n"
            str << "  <channel>\n"
            str << "    <title>#{Utils::TextUtils.escape_xml(feed_title)}</title>\n"
            str << "    <link>#{Utils::TextUtils.escape_xml(feed_home_url(config, base_path))}</link>\n"
            str << "    <description>#{Utils::TextUtils.escape_xml(config.description)}</description>\n"

            if language
              str << "    <language>#{Utils::TextUtils.escape_xml(language)}</language>\n"
            end

            str << "    <atom:link href=\"#{Utils::TextUtils.escape_xml(feed_url)}\" rel=\"self\" type=\"application/rss+xml\" />\n"

            pages.each do |page|
              str << "    <item>\n"
              # The root index commonly has an empty title; fall back to the site
              # title so the feed item is never `<title></title>` (mirrors llms.cr).
              item_title = page.title.empty? ? config.title : page.title
              str << "      <title>#{Utils::TextUtils.escape_xml(item_title)}</title>\n"

              full_url = page_full_url(page, base_url)
              escaped_url = Utils::TextUtils.escape_xml(full_url)
              str << "      <link>#{escaped_url}</link>\n"
              str << "      <guid>#{escaped_url}</guid>\n"

              # `<description>` is meant to be a summary. Prefer the
              # frontmatter description, then the rendered `summary`,
              # then a truncated body (gh#526).
              summary = summary_for_feed(page, config)
              str << "      <description>#{Utils::TextUtils.escape_xml(summary)}</description>\n"

              # Emit the full body in `<content:encoded>` when the user
              # opts into full content (default). CDATA so consumers
              # don't have to double-decode entities.
              if full_content
                full_html = full_content_for_feed(page, config)
                unless full_html.empty?
                  str << "      <content:encoded><![CDATA[#{escape_cdata(full_html)}]]></content:encoded>\n"
                end
              end

              if pub_date = page.date
                str << "      <pubDate>#{format_rfc822(pub_date)}</pubDate>\n"
              end

              # Frontmatter taxonomies (`tags`, `categories`, …) become
              # `<category>` elements (gh#526). RSS treats them as a
              # flat list, so we emit one per term across all
              # taxonomies. Tags first (matching the order most blogs
              # advertise), then any taxonomy values not already
              # represented.
              feed_categories(page).each do |term|
                str << "      <category>#{Utils::TextUtils.escape_xml(term)}</category>\n"
              end

              str << "    </item>\n"
            end

            str << "  </channel>\n"
            str << "</rss>\n"
          end
        end

        def self.generate_atom(
          pages : Array(Models::Page),
          config : Models::Config,
          filename : String,
          is_text : Bool,
          feed_title : String,
          base_path : String,
          language : String? = nil,
        ) : String
          base_url, feed_url = build_feed_url(config, base_path, filename)
          home_url = feed_home_url(config, base_path)
          # Atom <updated> must be deterministic: derive it from the newest
          # content date (updated||date) across entries rather than the build
          # wall-clock, so two builds of identical input stay byte-identical.
          # Falls back to the epoch sentinel when no entry carries a date.
          newest = pages.compact_map { |p| p.updated || p.date }.max?
          feed_updated = newest ? normalize_feed_time(newest) : Utils::SortUtils::FALLBACK_DATE
          # RFC 4287 §4.1.1: a feed MUST carry an author unless every entry
          # does. Emit a feed-level author unconditionally using the site title.
          feed_author = config.title.empty? ? feed_title : config.title

          String.build(500 + pages.size * 350) do |str|
            str << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"

            if language
              str << "<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"#{Utils::TextUtils.escape_xml(language)}\">\n"
            else
              str << "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
            end

            str << "  <title>#{Utils::TextUtils.escape_xml(feed_title)}</title>\n"
            str << "  <link href=\"#{Utils::TextUtils.escape_xml(home_url)}\" />\n"
            str << "  <link href=\"#{Utils::TextUtils.escape_xml(feed_url)}\" rel=\"self\" />\n"
            str << "  <updated>#{feed_updated.to_rfc3339}</updated>\n"
            str << "  <id>#{Utils::TextUtils.escape_xml(home_url)}</id>\n"

            unless feed_author.empty?
              str << "  <author><name>#{Utils::TextUtils.escape_xml(feed_author)}</name></author>\n"
            end

            if !config.description.empty?
              str << "  <subtitle>#{Utils::TextUtils.escape_xml(config.description)}</subtitle>\n"
            end

            pages.each do |page|
              str << "  <entry>\n"
              entry_title = page.title.empty? ? config.title : page.title
              str << "    <title>#{Utils::TextUtils.escape_xml(entry_title)}</title>\n"

              full_url = page_full_url(page, base_url)
              escaped_url = Utils::TextUtils.escape_xml(full_url)
              str << "    <link href=\"#{escaped_url}\" />\n"
              str << "    <id>#{escaped_url}</id>\n"

              entry_src = page.updated || page.date
              entry_date = entry_src ? normalize_feed_time(entry_src) : Utils::SortUtils::FALLBACK_DATE
              str << "    <updated>#{entry_date.to_rfc3339}</updated>\n"

              # Per-entry authors (RFC 4287). Raw author ids; the feed-level
              # author above guarantees validity for entries that carry none.
              page.authors.each do |author|
                next if author.strip.empty?
                str << "    <author><name>#{Utils::TextUtils.escape_xml(author)}</name></author>\n"
              end

              # Frontmatter taxonomies become Atom <category> elements,
              # mirroring the RSS feed's per-term <category> output (gh#526).
              feed_categories(page).each do |term|
                str << "    <category term=\"#{Utils::TextUtils.escape_xml(term)}\" />\n"
              end

              content = get_content_for_feed(page, config)
              content_type = is_text ? "text" : "html"
              str << "    <content type=\"#{content_type}\">#{Utils::TextUtils.escape_xml(content)}</content>\n"

              str << "  </entry>\n"
            end

            str << "</feed>\n"
          end
        end

        # Summary text for `<description>` / atom `<summary>`. Prefers
        # frontmatter `description`, falls back to a plain-text rendering of
        # the `<!-- more -->` summary, and finally to a plain-text excerpt
        # of the body (gh#526). The summary is stripped of markup so raw
        # markdown (`##` headings, code fences, math) never leaks into the
        # feed `<description>` (gh#491).
        private def self.summary_for_feed(page : Models::Page, config : Models::Config) : String
          if desc = page.description
            return desc unless desc.empty?
          end

          limit = config.feeds.truncate > 0 ? config.feeds.truncate : 300

          if summary_html = page.summary_html
            text = HTML.unescape(Utils::TextUtils.strip_html(summary_html)).strip
            return truncate_for_feed(text, limit) unless text.empty?
          end

          # Fall back to a stripped + truncated body. Prefer the
          # already-rendered HTML; degrade to the raw markdown only if
          # render hasn't run.
          html = page.content.empty? ? Processor::Markdown.render_body_cached(page.raw_content) : page.content
          text = HTML.unescape(Utils::TextUtils.strip_html(html)).strip
          truncate_for_feed(text, limit)
        end

        # Hard-truncate plain text to `limit` characters with an ellipsis.
        private def self.truncate_for_feed(text : String, limit : Int32) : String
          text.size > limit ? "#{text[0...limit]}..." : text
        end

        # Full HTML body suitable for `<content:encoded>` / atom
        # `<content type="html">`. Uses the already-rendered HTML when
        # available so we don't pay for a second markdown pass per page
        # (gh#526).
        private def self.full_content_for_feed(page : Models::Page, config : Models::Config) : String
          html = page.content.empty? ? Processor::Markdown.render_body_cached(page.raw_content) : page.content
          # Absolutize body links so <content:encoded> resolves out of page
          # context (root-relative AND document-relative). On an incremental
          # (--cache) build the render phase only rewrites links for pages it
          # re-renders; doing it here keeps the feed correct regardless of
          # cache state.
          absolutize_feed_html(html, page, config)
        end

        # Collect taxonomy terms that should appear as `<category>`
        # elements in the feed: `tags` first, then every other
        # taxonomy's terms not already emitted (gh#526). Deduplicated
        # while preserving order so the feed mirrors how the post
        # advertises itself.
        private def self.feed_categories(page : Models::Page) : Array(String)
          seen = Set(String).new
          result = [] of String
          page.tags.each do |tag|
            next if tag.empty?
            result << tag if seen.add?(tag)
          end
          page.taxonomies.each do |_, terms|
            terms.each do |term|
              next if term.empty?
              result << term if seen.add?(term)
            end
          end
          result
        end

        # Escape `]]>` so a body containing it can't terminate the CDATA
        # section early. Replaces `]]>` with `]]]]><![CDATA[>` (the
        # standard escape) so the run-on CDATA stays valid.
        private def self.escape_cdata(text : String) : String
          text.gsub("]]>", "]]]]><![CDATA[>")
        end

        private def self.get_content_for_feed(page : Models::Page, config : Models::Config) : String
          truncate = config.feeds.truncate
          full_content = config.feeds.full_content

          # When full_content is false, prefer the front matter description
          unless full_content
            if desc = page.description
              return desc unless desc.empty?
            end
            # Fall back to truncated content (default 300 chars)
            truncate = 300 if truncate <= 0
          end

          # Reuse already-rendered HTML from the Render phase when available,
          # avoiding an expensive duplicate Markdown → HTML conversion.
          html_content = if !page.content.empty?
                           page.content
                         else
                           Processor::Markdown.render_body_cached(page.raw_content)
                         end

          # Truncate if needed
          if truncate > 0
            # Strip HTML tags to get plain text for safe truncation, then decode
            # entities: this plain-text branch ends up in a `type="text"` Atom
            # element (and an RSS description), which consumers decode exactly
            # once — leaving `&amp;` here would double-escape to `&amp;amp;`.
            # Mirrors summary_for_feed's HTML.unescape.
            text_content = HTML.unescape(Utils::TextUtils.strip_html(html_content))
            if text_content.size > truncate
              text_content[0...truncate] + "..."
            else
              text_content # Return plain text even if not truncated for consistency
            end
          else
            # Full HTML (Atom <content type="html">). Absolutize body links so
            # they resolve out of page context, matching full_content_for_feed
            # on the RSS path.
            absolutize_feed_html(html_content, page, config)
          end
        end
      end
    end
  end
end
