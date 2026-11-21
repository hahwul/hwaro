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

      # Internal cache revision for changes to which entries go into which
      # shard. The public manifest version still describes the same schema.
      private MANIFEST_LAYOUT_KEY      = "_layout_revision"
      private MANIFEST_LAYOUT_REVISION = 1

      # Shard id for pages outside every section (`content/about.md`).
      ROOT_SHARD_ID = "_root"

      # Entry fields the generator knows how to emit; anything else in
      # `search.fields` is silently skipped, so the manifest's `fields` list
      # must be filtered the same way.
      KNOWN_FIELDS = %w[title content tags url section description]

      alias Entry = Hash(String, String | Array(String))
      private alias ShardKey = {id: String, language: String?, section: String?}
      private record ShardManifest, files : Array(String), current : Bool

      # An h2/h3 element of the rendered page, and the `id` attribute in its
      # attribute list (quote-aware: `title="a > b"` does not end the tag).
      # `split_by_heading` cuts the page body at these.
      SPLIT_HEADING_RE = /<h([23])\b(#{Utils::TextUtils::HTML_TAG_ATTRS_QUOTED_VALUES})>(.*?)<\/h\1\s*>/im
      HEADING_ID_ATTR  = /\sid\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))/i
      HTML_COMMENT     = /<!--.*?-->/m

      def self.manifest_path(output_dir : String) : String
        File.join(output_dir, SHARDS_DIR, MANIFEST_FILENAME)
      end

      # Every file the current config publishes, as it stands on disk after
      # `generate` ran (or skipped as unchanged): the classic index when a
      # single file is emitted, plus the manifest and each shard it lists.
      # The builder claims these, so a warm `--cache` build (or a serve
      # rebuild) removes what an earlier config published and this one does
      # not — `search.json` after `single_file = false` or a `filename`
      # change, the `search/` tree after `shards = "none"`, everything once
      # search is disabled.
      def self.published_outputs(config : Models::Config, output_dir : String) : Array(String)
        outputs = [] of String
        return outputs unless config.search.enabled
        if path = classic_index_path(config, output_dir)
          outputs << path
        end
        if config.search.sharded?
          manifest_file = manifest_path(output_dir)
          outputs << manifest_file
          shards_dir = File.join(output_dir, SHARDS_DIR)
          if manifest = read_shard_manifest(manifest_file)
            manifest.files.each do |name|
              if path = shard_output_path(shards_dir, name)
                outputs << path
              end
            end
          end
        end
        outputs
      end

      # Used by both Generate and the Render phase's cache hydration.
      def self.outputs_reusable?(config : Models::Config, output_dir : String) : Bool
        return true unless config.search.enabled
        return false if (path = classic_index_path(config, output_dir)) && !File.file?(path)
        return true unless config.search.sharded?

        manifest = read_shard_manifest(manifest_path(output_dir))
        return false unless manifest && manifest.current
        shards_dir = File.join(output_dir, SHARDS_DIR)
        manifest.files.all? do |name|
          (path = shard_output_path(shards_dir, name)) && File.file?(path)
        end
      end

      private def self.classic_index_path(config : Models::Config, output_dir : String) : String?
        # `single_file` only applies when shards are enabled.
        return if config.search.sharded? && !config.search.single_file
        File.join(output_dir, File.basename(config.search.filename))
      end

      private def self.shard_output_path(shards_dir : String, name : String) : String?
        path = File.join(shards_dir, name)
        path if Utils::OutputGuard.within_output_dir?(path, shards_dir)
      end

      def self.generate(pages : Array(Models::Page), config : Models::Config, output_dir : String, verbose : Bool = false, skip_if_unchanged : Bool = false, *, builder : Core::Build::Builder? = nil)
        return unless config.search.enabled

        sharded = config.search.sharded?
        search_path = classic_index_path(config, output_dir)

        if skip_if_unchanged && outputs_reusable?(config, output_dir)
          Logger.debug "  Search index unchanged (cache hit), skipping."
          return
        end

        # Filter out drafts, pages opted out of the index, `render = false`
        # pages, and auto-generated pages (e.g. taxonomy index/term listings).
        # The `render` check keeps the index in lockstep with the pages that
        # actually emit HTML; the `generated` check mirrors llms.cr so
        # navigational listing pages don't pollute search results. Both match
        # the guards sitemap.cr / feeds.cr / llms.cr already apply.
        search_pages = pages.reject { |p| !p.search_index_eligible? }
        # `[versions] search = "latest"` (default) keeps older versions out
        # of the index; "all" indexes every version (each record then
        # carries a `version` field for client-side filtering).
        search_pages.select! { |p| config.versions.in_search?(p) } if config.versions.enabled?

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
          write_shards(search_pages, [] of Array(Entry), config, output_dir, verbose, builder) if sharded
          # A warm `--cache`/serve build starts from the previous output, so
          # the classic file from when pages existed would keep publishing
          # content that is now a draft or opted out. Cold builds have no file.
          if search_path
            begin
              File.delete?(search_path)
            rescue File::Error
              # Best effort, like remove_stale_shard.
            end
          end
          return
        end

        # One group per page: its own record, then (split_by_heading) one
        # record per h2/h3 section. Shards keep a page's group together.
        groups = build_search_data(search_pages, config)
        search_data = groups.flat_map(&.itself)

        if search_path
          # Both libraries use the same array for now, so Hwaro generates a common format and lets the client build the index.
          # We've kept the names distinct to respect user intent and stay ready for library-specific optimizations later.
          content = case config.search.format.downcase
                    when "fuse_javascript"
                      generate_javascript(search_data)
                    when "fuse_json"
                      search_data.to_json
                    when "elasticlunr_json"
                      search_data.to_json
                    when "elasticlunr_javascript"
                      generate_javascript(search_data)
                    else
                      Logger.warn "Unknown search format '#{config.search.format}'. Defaulting to 'fuse_json'."
                      search_data.to_json
                    end

          # Write search file
          Hwaro::Utils::FileSafe.atomic_write(search_path, content)
          Logger.action :create, search_path if verbose
        end

        write_shards(search_pages, groups, config, output_dir, verbose, builder) if sharded
        Logger.info "  Generated search index with #{search_pages.size} pages." if verbose
      end

      # The entry keys every emitted entry carries, in emission order:
      # the configured fields (known ones only), then `url` (always
      # present) and `lang` (always appended). Exposed for the manifest.
      def self.entry_fields(config : Models::Config) : Array(String)
        fields = config.search.fields.map(&.downcase).select { |f| KNOWN_FIELDS.includes?(f) }.uniq!
        fields << "url" unless fields.includes?("url")
        fields << "lang" unless fields.includes?("lang")
        fields << "heading" if config.search.split_by_heading
        config.search.facets.each { |f| fields << f unless fields.includes?(f) }
        fields
      end

      # Truncate `text` to at most `max` characters, backing up to the last
      # whitespace inside the cut so no word is split. A run with no
      # whitespace at all (a long URL, untokenized CJK) is cut hard at `max`.
      # `max <= 0` disables truncation.
      def self.truncate_words(text : String, max : Int32) : String
        return text if max <= 0 || text.size <= max
        max = Utils::TextUtils.cluster_cut(text, max)
        cut = text[0, max]
        # A cut that already ends on a word boundary (the next character is
        # whitespace) keeps its last word; otherwise back up to the last
        # whitespace inside the cut. A first cluster kept whole can reach the
        # end of the text.
        unless (next_char = text[max]?).nil? || next_char.whitespace?
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
      private def self.shard_key(page : Models::Page, config : Models::Config) : ShardKey
        lang = page.language || config.default_language
        lang = "_default" if lang.empty?
        # NFC like the page URLs: the shard is an output name.
        top = Utils::PathUtils.nfc(page.section.split('/', remove_empty: true).first? || "")
        case config.search.shards
        when "language"
          {id: lang, language: lang, section: nil}
        when "section-language"
          {id: "#{lang}/#{top.empty? ? ROOT_SHARD_ID : top}", language: lang, section: top}
        else # "section"
          {id: top.empty? ? ROOT_SHARD_ID : top, language: nil, section: top}
        end
      end

      private def self.shard_keys_by_id(keys : Array(ShardKey)) : Hash(String, ShardKey)
        # The ordinary `_root` section shares the root pages' preferred id.
        # Reserve everyone else's ids first, then move that section only if
        # its own language already has a root-pages shard.
        preferred, root_sections = keys.partition { |key| key[:section] != ROOT_SHARD_ID }
        by_id = preferred.to_h { |key| {key[:id], key} }
        root_sections.each do |key|
          id = key[:id]
          dir, separator, stem = id.rpartition('/')
          while by_id.has_key?(id)
            stem = "_#{stem}"
            id = "#{dir}#{separator}#{stem}"
          end
          by_id[id] = key
        end
        by_id
      end

      # Emit `search/<id>.json` per shard plus the `search/index.json`
      # manifest. Shards are always plain JSON arrays whatever `format`
      # says: the `*_javascript` wrapper only serves `<script src>` loading,
      # and shards exist to be fetched on demand. Deterministic: shards are
      # written in id order and the manifest lists them the same way;
      # entries keep the order `search.json` uses.
      private def self.write_shards(pages : Array(Models::Page), entries : Array(Array(Entry)), config : Models::Config, output_dir : String, verbose : Bool, builder : Core::Build::Builder?) : Nil
        shards_dir = File.join(output_dir, SHARDS_DIR)
        manifest_file = manifest_path(output_dir)
        previous_files = read_shard_manifest(manifest_file).try(&.files) || [] of String

        groups = {} of ShardKey => Array(Entry)
        pages.each_with_index do |page, i|
          key = shard_key(page, config)
          (groups[key] ||= [] of Entry).concat(entries[i])
        end

        by_id = shard_keys_by_id(groups.keys)
        ids = by_id.keys.sort!
        root_ids, other_ids = ids.partition { |id| by_id[id][:section] == "" }
        files = shard_file_names(root_ids.concat(other_ids))
        base_path = config.base_path
        Hwaro::Utils::FileSafe.mkdir_p(shards_dir)
        manifest = JSON.build do |json|
          json.object do
            json.field "version", MANIFEST_VERSION
            json.field MANIFEST_LAYOUT_KEY, MANIFEST_LAYOUT_REVISION
            json.field "fields", entry_fields(config)
            json.field "shards" do
              json.array do
                ids.each do |id|
                  key = by_id[id]
                  group = groups[key]
                  content = group.to_json
                  name = files[id]
                  shard_file = File.join(shards_dir, name)
                  Hwaro::Utils::FileSafe.mkdir_p(File.dirname(shard_file))
                  Hwaro::Utils::FileSafe.atomic_write(shard_file, content)
                  Logger.action :create, shard_file if verbose
                  json.object do
                    json.field "id", id
                    # Percent-encode: a section directory may carry spaces
                    # or non-ASCII the filesystem accepts but a URL must escape.
                    json.field "url", "#{base_path}/#{SHARDS_DIR}/#{URI.encode_path(name)}"
                    json.field "language", key[:language]
                    json.field "section", key[:section]
                    json.field "count", group.size
                    json.field "bytes", content.bytesize
                  end
                end
              end
            end
          end
        end

        Hwaro::Utils::FileSafe.atomic_write(manifest_file, manifest)
        Logger.action :create, manifest_file if verbose

        # A surviving id can move to another file when the set of names
        # changes. Prune by the previous manifest's files, even in that case.
        # A build may still publish a static copy at a retired path.
        current = files.values.to_h { |name| {Utils::PathUtils.output_fold_key(name), name} }
        current[MANIFEST_FILENAME] = MANIFEST_FILENAME
        stale = [] of String
        (previous_files - files.values).each do |name|
          if replacement = current[Utils::PathUtils.output_fold_key(name)]?
            old_info = File.info?(File.join(shards_dir, name))
            new_info = File.info?(File.join(shards_dir, replacement))
            # On a case-folding filesystem the old spelling can now refer
            # to the file we just wrote under its new spelling.
            next if old_info && new_info && old_info.same_file?(new_info)
          end
          if builder
            path = File.join(shards_dir, name)
            next if Dir.exists?(path)
            next unless Utils::OutputGuard.safe_to_delete_file?(path, shards_dir)
            stale << path if Utils::OutputGuard.safe_to_delete_file?(path, output_dir)
          else
            remove_stale_shard(shards_dir, name)
          end
        end
        builder.try &.prune_unclaimed_outputs(stale, output_dir, keep_raw_copies: false)
      end

      private def self.shard_file_names(ids : Array(String)) : Hash(String, String)
        names = {} of String => String
        taken = Set{MANIFEST_FILENAME}
        # Preserve the established filename for a shard literally named
        # `index`. Claim all other available natural names before assigning
        # alternatives, so a fallback cannot displace an unrelated shard.
        if ids.includes?("index")
          names["index"] = "_index.json"
          taken << "_index.json"
        end
        conflicts = [] of String
        ids.each do |id|
          next if names.has_key?(id)
          name = "#{id}.json"
          if taken.add?(Utils::PathUtils.output_fold_key(name))
            names[id] = name
          else
            conflicts << id
          end
        end
        conflicts.each do |id|
          dir, separator, stem = id.rpartition('/')
          loop do
            stem = "_#{stem}"
            name = "#{dir}#{separator}#{stem}.json"
            if taken.add?(Utils::PathUtils.output_fold_key(name))
              names[id] = name
              break
            end
          end
        end
        names
      end

      private def self.read_shard_manifest(manifest_file : String) : ShardManifest?
        return unless File.file?(manifest_file)
        parsed = JSON.parse(File.read(manifest_file)).as_h? || return
        shards = parsed["shards"]?.try(&.as_a?) || return
        files = shards.compact_map do |shard|
          next unless fields = shard.as_h?
          next unless (id = fields["id"]?.try(&.as_s?)) && (url = fields["url"]?.try(&.as_s?))
          dir, separator, stem = id.rpartition('/')
          filename = URI.decode(url.rpartition('/').last)
          natural = "#{stem}.json"
          # A generated URL can only add underscores before the id's
          # basename. Match its suffix, since the site's base path may have
          # changed and may itself contain a `/search/` segment.
          next unless filename.ends_with?(natural) && filename.rchop(natural).each_char.all? { |char| char == '_' }
          name = "#{dir}#{separator}#{filename}"
          next if name == MANIFEST_FILENAME || name.includes?('\u0000') || name.includes?('\\')
          path = Path.posix(name)
          next unless path.relative? && path.normalize.to_s == name
          name if url.ends_with?("/#{SHARDS_DIR}/#{URI.encode_path(name)}")
        end.uniq!
        current = parsed["version"]?.try(&.as_i64?) == MANIFEST_VERSION &&
                  parsed[MANIFEST_LAYOUT_KEY]?.try(&.as_i64?) == MANIFEST_LAYOUT_REVISION &&
                  !parsed["fields"]?.try(&.as_a?).nil? && files.size == shards.size
        ShardManifest.new(files, current)
      rescue JSON::ParseException | File::Error
        nil
      end

      private def self.remove_stale_shard(shards_dir : String, name : String) : Nil
        root = File.expand_path(shards_dir)
        path = File.expand_path(File.join(shards_dir, name))
        return unless Utils::OutputGuard.safe_to_delete_file?(path, root)
        File.delete?(path)
        # Drop now-empty nested id directories (`search/ko/`) best-effort.
        dir = File.dirname(path)
        while dir != root && Utils::PathUtils.within?(dir, root)
          break unless Dir.empty?(dir)
          Dir.delete(dir)
          dir = File.dirname(dir)
        end
      rescue File::Error | ArgumentError
        # Best effort: a stale shard is harmless, a failed build is not.
        # ArgumentError: an id holding a NUL (a manifest shipped from
        # `static/`) names no file, and building its path raises.
      end

      private def self.build_search_data(pages : Array(Models::Page), config : Models::Config) : Array(Array(Entry))
        # Pre-lowercase field names once instead of per-page per-field
        fields = config.search.fields.map(&.downcase)
        cjk = config.search.tokenize_cjk
        max_content = config.search.content_max_length

        # Extract base path from base_url for subpath deployments. Use the
        # memoized Config helper rather than re-parsing: it also rescues a
        # malformed base_url (a bare `URI.parse` raised out of the generator
        # and aborted the build) and normalizes a "/" path to "".
        base_path = config.base_path

        split = config.search.split_by_heading
        facets = config.search.facets

        pages.map do |page|
          data = Entry.new
          html_content = nil

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
              title = Utils::TextUtils.nfc(page.title.empty? ? config.title : page.title)
              data["title"] = cjk ? Utils::TextUtils.tokenize_cjk(title) : title
            when "content"
              html_content = page_html(page, config)
              data["content"] = plain_text(html_content, cjk, max_content)
            when "tags"
              data["tags"] = page.tags
            when "url"
              data["url"] = base_path + page.url
            when "section"
              data["section"] = page.section
            when "description"
              desc = Utils::TextUtils.nfc(page.description || "")
              data["description"] = cjk ? Utils::TextUtils.tokenize_cjk(desc) : desc
            end
          end

          # Always include URL even if not in fields list
          data["url"] = base_path + page.url unless data.has_key?("url")

          # Always include the page language so the client can scope results
          # to the current language (mirrors per-language feeds).
          data["lang"] = page.language || config.default_language
          if version = page.version
            data["version"] = version.name
          end

          # `lang` is already on every record.
          facets.each do |facet|
            case facet
            when "lang"    then next
            when "section" then data["section"] = page.section
            when "tags"    then data["tags"] = page.tags
            else                data[facet] = page.taxonomy_values(facet)
            end
          end

          group = [data]
          if split
            html_content ||= page_html(page, config)
            title = data["title"]? || begin
              raw_title = Utils::TextUtils.nfc(page.title.empty? ? config.title : page.title)
              cjk ? Utils::TextUtils.tokenize_cjk(raw_title) : raw_title
            end
            page_url = data["url"].as(String)
            heading_sections(html_content).each do |section|
              record = data.dup
              record["url"] = "#{page_url}##{section[:id]}"
              record["title"] = title
              record["heading"] = plain_text(section[:heading], cjk, 0)
              record["content"] = plain_text(section[:body], cjk, max_content)
              group << record
            end
          end
          group
        end
      end

      # The page body as HTML. Reuses the rendered content when available;
      # the fallback passes the site's markdown options so cache-hit pages
      # index the same text a rendered page produces (safe-mode HTML
      # stripping, emoji, extensions).
      private def self.page_html(page : Models::Page, config : Models::Config) : String
        return page.content unless page.content.empty?
        md = config.markdown
        hooks = Content::Processors::RenderHooks.fallback_context(page, config)
        Processor::Markdown.render_body_cached(page.raw_content, safe: md.safe, emoji: md.emoji, lazy_loading: md.lazy_loading, markdown_config: md,
          hooks: hooks, hooks_key: "#{page.url}:#{page.language}")
      end

      # Strip HTML tags AND decode entities so the index stores actual
      # characters (`print("hi")`) rather than the HTML-escaped form
      # (`print(&quot;hi&quot;)`): client-side search matches on the raw
      # stored string. Truncation runs after CJK tokenization so the cap
      # bounds what actually lands in the file.
      private def self.plain_text(html : String, cjk : Bool, max : Int32) : String
        text = Utils::TextUtils.nfc(HTML.unescape(Utils::TextUtils.strip_html(html)))
        text = Utils::TextUtils.tokenize_cjk(text) if cjk
        truncate_words(text, max)
      end

      # The h2/h3 sections of a rendered page body, in document order: each
      # heading's real `id` (as the page's own anchor links use it), its
      # inner HTML, and the HTML up to the next h2/h3. A heading without an
      # id still ends the previous section but yields no record: it has no
      # anchor to link to.
      def self.heading_sections(html : String) : Array({id: String, heading: String, body: String})
        sections = [] of {id: String, heading: String, body: String}
        return sections unless html.includes?("<h") || html.includes?("<H")
        # A heading inside an HTML comment has no anchor on the page.
        html = html.gsub(HTML_COMMENT, "") if html.includes?("<!--")
        matches = [] of Regex::MatchData
        html.scan(SPLIT_HEADING_RE) { |m| matches << m }
        matches.each_with_index do |m, i|
          next unless attr = m[2].match(HEADING_ID_ATTR)
          id = HTML.unescape(attr[1]? || attr[2]? || attr[3]? || "")
          next if id.empty?
          start = m.byte_end(0)
          stop = matches[i + 1]?.try(&.byte_begin(0)) || html.bytesize
          sections << {id: id, heading: m[3], body: html.byte_slice(start, stop - start)}
        end
        sections
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
