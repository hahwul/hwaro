require "../models/page"
require "./discovery_pages"
require "../models/config"
require "../utils/logger"
require "../utils/text_utils"
require "./processors/markdown"
require "html"
require "json"
require "uri"

module Hwaro
  module Content
    class Search
      # Sharded output lives under `<output_dir>/search/`: one
      # `<shard-id>.json` per shard plus this manifest. Fixed names (not
      # derived from `filename`) so a client can discover the layout from a
      # single well-known URL.
      SHARDS_DIR        = "search"
      MANIFEST_FILENAME = "index.json"
      MANIFEST_VERSION  = 1

      # Shard id for pages outside every section (`content/about.md`).
      ROOT_SHARD_ID = "_root"

      # Entry fields the generator knows how to emit; anything else in
      # `search.fields` is silently skipped, so the manifest's `fields` list
      # must be filtered the same way.
      KNOWN_FIELDS = %w[title content tags url section description]

      alias Entry = Hash(String, String | Array(String))

      def self.manifest_path(output_dir : String) : String
        File.join(output_dir, SHARDS_DIR, MANIFEST_FILENAME)
      end

      def self.generate(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false, skip_if_unchanged : Bool = false)
        return unless config.search.enabled

        sharded = config.search.sharded?
        # With shards on, `single_file = false` drops the classic file; with
        # shards off the setting is meaningless and the classic file is the
        # only output (byte-identical to pre-shard builds).
        single_file = !sharded || config.search.single_file
        search_path = File.join(output_dir, File.basename(config.search.filename))

        if skip_if_unchanged
          present = (!single_file || File.exists?(search_path)) &&
                    (!sharded || File.exists?(manifest_path(output_dir)))
          if present
            Logger.debug "  Search index unchanged (cache hit), skipping."
            return
          end
        end

        # Filter out drafts, pages opted out of the index, `render = false`
        # pages, and auto-generated pages (e.g. taxonomy index/term listings).
        # The `render` check keeps the index in lockstep with the pages that
        # actually emit HTML; the `generated` check mirrors llms.cr so
        # navigational listing pages don't pollute search results. Both match
        # the guards sitemap.cr / feeds.cr / llms.cr already apply.
        search_pages = pages.reject { |p| !p.search_index_eligible? }

        search_pages = DiscoveryPages.dedupe_by_url(search_pages)
        DiscoveryPages.reject_excluded!(search_pages, config.search.exclude)

        # Multilingual: honor each language's `build_search_index` toggle so a
        # language opted out is excluded from the index. Pages without an
        # explicit language fall back to the default language.
        if config.multilingual?
          default_lang = config.default_language
          search_pages.reject! do |page|
            lang_config = config.language(page.language || default_lang)
            lang_config ? !lang_config.build_search_index : false
          end
        end

        if search_pages.empty?
          Logger.info "  No pages to include in search index."
          # An empty manifest still tells a sharded client "nothing to
          # load" instead of a 404, and pruning drops shards a previous
          # build wrote for pages that no longer exist.
          write_shards(search_pages, [] of Entry, config, output_dir, verbose) if sharded
          return
        end

        # Build search data based on format
        search_data = build_search_data(search_pages, config)

        if single_file
          # Both libraries use the same array for now, so Hwaro generates a common format and lets the client build the index.
          # We've kept the names distinct to respect user intent and stay ready for library-specific optimizations later.
          content = case config.search.format.downcase
                    when "fuse_javascript"
                      generate_javascript(search_data)
                    when "fuse_json"
                      generate_json(search_data)
                    when "elasticlunr_json"
                      generate_json(search_data)
                    when "elasticlunr_javascript"
                      generate_javascript(search_data)
                    else
                      Logger.warn "Unknown search format '#{config.search.format}'. Defaulting to 'fuse_json'."
                      generate_json(search_data)
                    end

          # Write search file
          Hwaro::Utils::FileSafe.atomic_write(search_path, content)
          Logger.action :create, search_path if verbose
        end

        write_shards(search_pages, search_data, config, output_dir, verbose) if sharded
        Logger.info "  Generated search index with #{search_pages.size} pages." if verbose
      end

      # The entry keys every emitted entry carries, in emission order:
      # the configured fields (known ones only), then `url` (always
      # present) and `lang` (always appended). Exposed for the manifest.
      def self.entry_fields(config : Models::Config) : Array(String)
        fields = config.search.fields.map(&.downcase).select { |f| KNOWN_FIELDS.includes?(f) }.uniq!
        fields << "url" unless fields.includes?("url")
        fields << "lang" unless fields.includes?("lang")
        fields
      end

      # Truncate `text` to at most `max` characters, backing up to the last
      # whitespace inside the cut so no word is split. A run with no
      # whitespace at all (a long URL, untokenized CJK) is cut hard at `max`.
      # `max <= 0` disables truncation.
      def self.truncate_words(text : String, max : Int32) : String
        return text if max <= 0 || text.size <= max
        cut = text[0, max]
        # A cut that already ends on a word boundary (the next character is
        # whitespace) keeps its last word; otherwise back up to the last
        # whitespace inside the cut.
        unless text[max].whitespace?
          if idx = cut.rindex(/\s/)
            cut = cut[0, idx] if idx > 0
          end
        end
        cut.rstrip
      end

      # Shard identity for one page under the configured `shards` mode.
      # `section` is the page's TOP-LEVEL section (`blog` for `blog/news`)
      # because that is the granularity a client can lazy-load by; nested
      # sections would explode the shard count without helping.
      private def self.shard_key(page : Models::Page, config : Models::Config) : {id: String, language: String?, section: String?}
        lang = page.language || config.default_language
        lang = "_default" if lang.empty?
        top = page.section.split('/', remove_empty: true).first? || ""
        case config.search.shards
        when "language"
          {id: lang, language: lang, section: nil}
        when "section-language"
          {id: "#{lang}/#{top.empty? ? ROOT_SHARD_ID : top}", language: lang, section: top}
        else # "section"
          {id: top.empty? ? ROOT_SHARD_ID : top, language: nil, section: top}
        end
      end

      # Emit `search/<id>.json` per shard plus the `search/index.json`
      # manifest. Shards are always plain JSON arrays whatever `format`
      # says: the `*_javascript` wrapper only serves `<script src>` loading,
      # and shards exist to be fetched on demand. Deterministic: shards are
      # written in id order and the manifest lists them the same way;
      # entries keep the order `search.json` uses.
      private def self.write_shards(pages : Array(Models::Page), entries : Array(Entry), config : Models::Config, output_dir : String, verbose : Bool) : Nil
        shards_dir = File.join(output_dir, SHARDS_DIR)
        manifest_file = manifest_path(output_dir)
        previous_ids = previous_shard_ids(manifest_file)

        groups = {} of String => {language: String?, section: String?, entries: Array(Entry)}
        pages.each_with_index do |page, i|
          key = shard_key(page, config)
          group = groups[key[:id]] ||= {language: key[:language], section: key[:section], entries: [] of Entry}
          group[:entries] << entries[i]
        end

        base_path = config.base_path
        Hwaro::Utils::FileSafe.mkdir_p(shards_dir)
        manifest = JSON.build do |json|
          json.object do
            json.field "version", MANIFEST_VERSION
            json.field "fields", entry_fields(config)
            json.field "shards" do
              json.array do
                groups.keys.sort!.each do |id|
                  group = groups[id]
                  content = group[:entries].to_json
                  shard_file = File.join(shards_dir, "#{id}.json")
                  Hwaro::Utils::FileSafe.mkdir_p(File.dirname(shard_file))
                  Hwaro::Utils::FileSafe.atomic_write(shard_file, content)
                  Logger.action :create, shard_file if verbose
                  json.object do
                    json.field "id", id
                    # Percent-encode: a section directory may carry spaces
                    # or non-ASCII the filesystem accepts but a URL must escape.
                    json.field "url", "#{base_path}/#{SHARDS_DIR}/#{URI.encode_path(id)}.json"
                    json.field "language", group[:language]
                    json.field "section", group[:section]
                    json.field "count", group[:entries].size
                    json.field "bytes", content.bytesize
                  end
                end
              end
            end
          end
        end

        # Prune shards a previous build listed that this build did not
        # write (a removed section/language) so a warm `--cache` build or a
        # `serve` rebuild never leaves a shard the manifest no longer knows.
        # Only ids from OUR previous manifest are touched, never arbitrary
        # files under `search/`.
        (previous_ids - groups.keys).each { |id| remove_stale_shard(shards_dir, id) }

        Hwaro::Utils::FileSafe.atomic_write(manifest_file, manifest)
        Logger.action :create, manifest_file if verbose
      end

      private def self.previous_shard_ids(manifest_file : String) : Array(String)
        return [] of String unless File.file?(manifest_file)
        parsed = JSON.parse(File.read(manifest_file))
        parsed["shards"].as_a.compact_map { |s| s["id"]?.try(&.as_s?) }
      rescue JSON::ParseException | KeyError | TypeCastError | File::Error
        [] of String
      end

      private def self.remove_stale_shard(shards_dir : String, id : String) : Nil
        root = File.expand_path(shards_dir)
        path = File.expand_path(File.join(shards_dir, "#{id}.json"))
        # A hand-edited manifest could smuggle `..` into an id; never delete
        # outside the shard directory.
        return unless path.starts_with?(root + File::SEPARATOR)
        File.delete?(path)
        # Drop now-empty nested id directories (`search/ko/`) best-effort.
        dir = File.dirname(path)
        while dir != root && dir.starts_with?(root + File::SEPARATOR)
          break unless Dir.empty?(dir)
          Dir.delete(dir)
          dir = File.dirname(dir)
        end
      rescue File::Error
        # Best effort: a stale shard is harmless, a failed build is not.
      end

      private def self.build_search_data(pages : Array(Models::Page), config : Models::Config) : Array(Entry)
        # Pre-lowercase field names once instead of per-page per-field
        fields = config.search.fields.map(&.downcase)
        cjk = config.search.tokenize_cjk
        max_content = config.search.content_max_length

        # Extract base path from base_url for subpath deployments. Use the
        # memoized Config helper rather than re-parsing: it also rescues a
        # malformed base_url (a bare `URI.parse` raised out of the generator
        # and aborted the build) and normalizes a "/" path to "".
        base_path = config.base_path

        pages.map do |page|
          data = Entry.new

          fields.each do |field|
            case field
            when "title"
              # The root index commonly has an empty title; fall back to the
              # site title so the search entry isn't blank (mirrors llms.cr/feeds).
              # Store the title verbatim: it is plain frontmatter text, and
              # stripping "tags" from it destroyed titles like `Using <canvas>`.
              # XSS safety is the renderer's job — every bundled search UI
              # escapes via escapeHtml() before innerHTML (like feeds escape
              # via escape_xml), so defense belongs there, not in the data.
              title = page.title.empty? ? config.title : page.title
              data["title"] = cjk ? Utils::TextUtils.tokenize_cjk(title) : title
            when "content"
              # Convert markdown to plain text
              # Optimization: Reuse rendered content if available. The
              # fallback passes the site's markdown options so cache-hit
              # pages index the same text a rendered page produces
              # (safe-mode HTML stripping, emoji, extensions).
              if !page.content.empty?
                html_content = page.content
              else
                md = config.markdown
                hooks = Content::Processors::RenderHooks.fallback_context(page, config)
                html_content = Processor::Markdown.render_body_cached(page.raw_content, safe: md.safe, emoji: md.emoji, lazy_loading: md.lazy_loading, markdown_config: md,
                  hooks: hooks, hooks_key: "#{page.url}:#{page.language}")
              end

              # Strip HTML tags AND decode entities so the index stores
              # actual characters (`print("hi")`) rather than the HTML-
              # escaped form (`print(&quot;hi&quot;)`). Client-side
              # search libraries match on the raw stored string.
              text_content = HTML.unescape(Utils::TextUtils.strip_html(html_content))
              text_content = Utils::TextUtils.tokenize_cjk(text_content) if cjk
              # Truncate the stored value (after CJK tokenization) so the
              # configured cap bounds what actually lands in the file.
              data["content"] = truncate_words(text_content, max_content)
            when "tags"
              data["tags"] = page.tags
            when "url"
              data["url"] = base_path + page.url
            when "section"
              data["section"] = page.section
            when "description"
              desc = page.description || ""
              data["description"] = cjk ? Utils::TextUtils.tokenize_cjk(desc) : desc
            end
          end

          # Always include URL even if not in fields list
          data["url"] = base_path + page.url unless data.has_key?("url")

          # Always include the page language so the client can scope results
          # to the current language (mirrors per-language feeds).
          data["lang"] = page.language || config.default_language

          data
        end
      end

      private def self.generate_json(search_data : Array(Entry)) : String
        search_data.to_json
      end

      private def self.generate_javascript(search_data : Array(Entry)) : String
        json_str = search_data.to_json
        # Avoid double-alloc: skip gsub when no </script> escape is needed (common case)
        if json_str.includes?("</")
          "var searchData = #{json_str.gsub("</", "<\\/")};"
        else
          "var searchData = #{json_str};"
        end
      end
    end
  end
end
