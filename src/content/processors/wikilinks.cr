# Obsidian-style `[[wikilinks]]` and `![[embeds]]` (`[markdown] wikilinks`).
#
# The rewrite runs on the page's Markdown after shortcode expansion and
# before Markd: a resolved link becomes an ordinary `[text](@/path.md#slug)`
# link and an image embed an ordinary `![alt](url)` image, so the `@/`
# resolver, render hooks, `base_path`, the external-link policy and the
# `[links]` checks all apply unchanged. Nothing is rewritten where Markd
# would not parse a link either: fenced or indented code and raw HTML blocks
# (FenceTracker), code spans, HTML comments (which also covers shortcode
# placeholders), HTML tags, backslash escapes, and math when `[markdown]
# math` is on (the math pass's own stash).

require "html"
require "./fence_tracker"
require "./markdown_extensions"
require "../../models/page"
require "../../utils/byte_scan"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Processors
      module Wikilinks
        extend self

        # Tokens kept verbatim, matched over one paragraph-sized chunk: a
        # code span (which may cross a line break), an HTML comment, an HTML
        # tag (Markd's grammar, so attribute values are never rewritten) and
        # a backslash escape (`\[[x]]` stays literal).
        VERBATIM_TOKENS = [
          /(?<code>`+)(?s:.*?)(?<!`)\k<code>(?!`)/.source,
          /(?<comment><!--(?s:.*?)-->)/.source,
          "(?<tag>#{MarkdownExtensions::HTML_TAG_RE.source})",
        ].join('|')
        ESC_TOKEN = /(?<esc>\\[^\n])/.source
        # `\(…\)` TeX math, kept verbatim with `[markdown] math` (the `$`
        # forms are stashed by MarkdownExtensions.protect_math). Precedes
        # ESC_TOKEN, which would otherwise take its `\(`.
        TEX_TOKEN      = /(?<tex>\\\((?s:.*?)\\\))/.source
        WIKILINK_TOKEN = /(?<bang>!?)\[\[(?<inner>[^\[\]\n]+)\]\]/.source
        # The other link form backlinks count: a Markdown destination. HTML
        # `href`s are read out of the `tag` token.
        URL_TOKEN = /\]\(\s*<?(?<url>[^\s)>]+)/.source
        HREF_RE   = /\bhref\s*=\s*["']([^"']*)["']/i

        WIKILINK_TOKEN_RE      = Regex.new("#{VERBATIM_TOKENS}|#{ESC_TOKEN}|#{WIKILINK_TOKEN}")
        WIKILINK_MATH_TOKEN_RE = Regex.new("#{VERBATIM_TOKENS}|#{TEX_TOKEN}|#{ESC_TOKEN}|#{WIKILINK_TOKEN}")
        LINK_TOKEN_RE          = Regex.new("#{VERBATIM_TOKENS}|#{ESC_TOKEN}|#{WIKILINK_TOKEN}|#{URL_TOKEN}")
        LINK_MATH_TOKEN_RE     = Regex.new("#{VERBATIM_TOKENS}|#{TEX_TOKEN}|#{ESC_TOKEN}|#{WIKILINK_TOKEN}|#{URL_TOKEN}")

        IMAGE_EXT_RE = /\.(?:png|jpe?g|gif|webp|svg|avif|bmp|ico|tiff?)\z/i
        SIZE_RE      = /\A(\d+)(?:x(\d+))?\z/

        # A parsed `[[target#heading|label]]`. `heading` is nil for a plain
        # link and for a block ref (`#^id`), which links to the page itself.
        record Link, embed : Bool, target : String, heading : String?, label : String? do
          # The alias, or else the target as Obsidian displays it.
          def text : String
            if l = label
              return l
            end
            h = heading
            return target unless h
            target.empty? ? h : "#{target} > #{h}"
          end

          def image? : Bool
            embed && target.matches?(IMAGE_EXT_RE)
          end

          # A target naming a non-page file (`doc.pdf`, `photo.png`).
          def file? : Bool
            !File.extname(target).downcase.in?("", ".md", ".markdown")
          end
        end

        def parse(inner : String, embed : Bool) : Link?
          target, label = inner, nil
          if bar = inner.index('|')
            # Inside a table the alias pipe is escaped as `\|`.
            target = inner[0, bar].rchop('\\')
            label = inner[(bar + 1)..].strip.presence
          end
          heading = nil
          if hash = target.index('#')
            heading = target[(hash + 1)..].strip
            heading = nil if heading.empty? || heading.starts_with?('^')
            target = target[0, hash]
          end
          target = target.strip
          return if target.empty? && heading.nil?
          Link.new(embed, target, heading, label)
        end

        # The {source, target} pairs already warned about. Owned by the
        # Builder so a serve session warns once, not on every rebuild.
        class WarnLog
          @seen = Set({String, String}).new
          @mutex = Mutex.new

          def first?(source : String, target : String) : Bool
            @mutex.synchronize { @seen.add?({source, target}) }
          end

          def clear : Nil
            @mutex.synchronize { @seen.clear }
          end
        end

        # Lookup key: NFC (a file name saved decomposed still matches a link
        # typed composed) and lowercase.
        def self.key(text : String) : String
          text.unicode_normalize(:nfc).downcase
        end

        # Page and file lookup for one page set. Read-only after construction
        # except for the lazily built file index, behind the mutex (render
        # workers share one index).
        class Index
          @by_name = {} of String => Array(Models::Page)
          @by_path = {} of String => Array(Models::Page)
          @files : Hash(String, Array({String, String}))? = nil
          @mutex = Mutex.new

          # `files` lists every published non-page file as
          # `{relative path, URL}`; it is only called on the first file link
          # that is not one of the source page's own bundle assets.
          def initialize(pages : Enumerable(Models::Page), default_language : String,
                         @files_source : Proc(Array({String, String})) = -> { [] of {String, String} },
                         @warned : WarnLog = WarnLog.new)
            pages.each do |page|
              next unless keys = Index.keys_for(page, default_language)
              (@by_name[keys[0]] ||= [] of Models::Page) << page
              (@by_path[keys[1]] ||= [] of Models::Page) << page
            end
          end

          # `{name, content path}` a page answers to, lowercased: the file
          # stem without extension and language suffix (the directory name
          # for a bundle or section index), and the content-relative path
          # without them. nil for the root index.
          def self.keys_for(page : Models::Page, default_language : String) : {String, String}?
            dir = File.dirname(page.path)
            dir = "" if dir == "."
            base = File.basename(page.path)
            stem = base.rchop(File.extname(base))
            lang = ".#{page.language || default_language}"
            stem = stem.rchop(lang) if stem.ends_with?(lang)
            if page.is_index
              return if dir.empty?
              {Wikilinks.key(File.basename(dir)), Wikilinks.key(dir)}
            else
              {Wikilinks.key(stem), Wikilinks.key(dir.empty? ? stem : "#{dir}/#{stem}")}
            end
          end

          def resolve(target : String, source : Models::Page) : Models::Page?
            key = Wikilinks.key(target.strip.lchop('/').rchop('/')).rchop(".markdown").rchop(".md")
            return if key.empty?
            list = key.includes?('/') ? @by_path[key]? : @by_name[key]?
            return unless list
            return list.first if list.size == 1
            same = list.select { |c| c.language == source.language }
            pick(same.empty? ? list : same, source, target) { |c| {c.path, Index.container_dir(c)} }
          end

          # The URL of the file an embed names: one of the source page's own
          # bundle assets (relative), else a published file anywhere.
          def resolve_file(target : String, source : Models::Page) : String?
            want = Wikilinks.key(target.strip.lchop('/'))
            return if want.empty?
            unless source.assets.empty?
              bundle = File.dirname(source.path)
              own = source.assets.compact_map do |asset|
                rel = asset.lchop("#{bundle}/")
                rel if file_matches?(rel, want)
              end
              unless own.empty?
                return pick(own, source, target) { |rel| {rel, File.dirname(rel)} }
              end
            end
            files = @mutex.synchronize { @files ||= index_files }
            list = files[File.basename(want)]?.try(&.select { |entry| file_matches?(entry[0], want) })
            return if list.nil? || list.empty?
            pick(list, source, target) { |entry| {entry[0], File.dirname(entry[0])} }[1]
          end

          private def file_matches?(rel : String, want : String) : Bool
            low = Wikilinks.key(rel)
            want.includes?('/') ? low == want || low.ends_with?("/#{want}") : File.basename(low) == want
          end

          private def index_files : Hash(String, Array({String, String}))
            map = {} of String => Array({String, String})
            @files_source.call.each do |entry|
              (map[Wikilinks.key(File.basename(entry[0]))] ||= [] of {String, String}) << entry
            end
            map
          end

          # Ambiguity: same directory as the source first, then the shortest
          # path, then lexicographic order; warned once per source and target.
          # The caller has already narrowed pages to the source's language.
          private def pick(list : Array(T), source : Models::Page, target : String, & : T -> {String, String}) : T forall T
            return list.first if list.size == 1
            src_dir = Index.container_dir(source)
            keyed = list.map { |c| path, dir = yield(c); {c, path, dir} }
            chosen = keyed.min_by { |_, path, dir| {dir == src_dir ? 0 : 1, path.size, path} }
            if @warned.first?(source.path, target)
              Logger.warn "Ambiguous wikilink '[[#{target}]]' in '#{source.path}' matches #{keyed.map(&.[1]).sort!.join(", ")}; using '#{chosen[1]}'."
            end
            chosen[0]
          end

          # The directory a page sits in: a bundle or section index counts as
          # living beside its siblings, in its directory's parent.
          def self.container_dir(page : Models::Page) : String
            dir = File.dirname(page.path)
            dir = File.dirname(dir) if page.is_index
            dir == "." ? "" : dir
          end
        end

        # Rewrite every wikilink in `content` (see the file comment). An
        # unresolved one renders as a `wikilink-missing` span (plain text in
        # safe mode), is warned about, and is appended to `misses` as
        # `{"[[…]]" source text, reason}`.
        def rewrite(content : String, source : Models::Page, index : Index, safe : Bool = false,
                    misses : Array({String, String})? = nil, warn : Bool = true, math : Bool = false) : String
          return content unless Utils::ByteScan.includes?(content, "[[")
          scan(content, math, math ? WIKILINK_MATH_TOKEN_RE : WIKILINK_TOKEN_RE) do |md|
            next unless inner = md["inner"]?
            next unless link = parse(inner, md["bang"] == "!")
            render(link, md[0], source, index, safe, misses, warn)
          end
        end

        # Yields every link-ish token where `rewrite` would see one: a parsed
        # wikilink, or the URL of a Markdown destination / HTML href.
        def each_link(content : String, math : Bool = false, & : Link | String ->) : Nil
          return unless Utils::ByteScan.includes?(content, "[[") || Utils::ByteScan.includes?(content, "](") ||
                        Utils::ByteScan.includes?(content, "href")
          scan(content, math, math ? LINK_MATH_TOKEN_RE : LINK_TOKEN_RE) do |md|
            if inner = md["inner"]?
              parse(inner, md["bang"] == "!").try { |link| yield link }
            elsif url = md["url"]?
              yield url
            elsif tag = md["tag"]?
              tag.scan(HREF_RE) { |m| yield m[1] }
            end
            nil
          end
        end

        private def render(link : Link, source_text : String, source : Models::Page, index : Index, safe : Bool,
                           misses : Array({String, String})?, warn : Bool) : String
          if link.image?
            if url = index.resolve_file(link.target, source)
              return image(link, url)
            end
          elsif link.target.empty?
            return "[#{escape_text(link.text)}](##{encode(slug(link.heading))})"
          elsif page = index.resolve(link.target, source)
            dest = "@/#{encode(page.path)}"
            dest += "##{encode(slug(link.heading))}" if link.heading
            return "[#{escape_text(link.text)}](#{dest})"
          elsif link.file? && (url = index.resolve_file(link.target, source))
            # An attachment (`[[doc.pdf]]`, `![[doc.pdf]]`): a plain link.
            return "[#{escape_text(link.text)}](#{encode(url)})"
          end

          reason = link.file? ? "file not found" : "page not found"
          Logger.warn "Wikilink '#{source_text}' in '#{source.path}' could not be resolved: #{reason}." if warn
          misses << {source_text, reason} if misses
          safe ? escape_text(link.text) : %(<span class="wikilink wikilink-missing">#{HTML.escape(link.text)}</span>)
        end

        # `|300` / `|300x200` sizes the image through an attribute block
        # (MarkdownExtensions enables image attributes with wikilinks); any
        # other alias is the alt text, which otherwise is the file name.
        private def image(link : Link, url : String) : String
          label = link.label
          size = label.try(&.match(SIZE_RE))
          alt = label && !size ? label : File.basename(link.target)
          String.build do |io|
            io << "![" << escape_text(alt) << "](" << encode(url) << ')'
            if size
              io << "{width=" << size[1]
              size[2]?.try { |h| io << " height=" << h }
              io << '}'
            end
          end
        end

        # Same rule HeadingIds applies to a rendered heading, so the
        # fragment matches the id the target's heading gets.
        private def slug(heading : String?) : String
          s = Utils::TextUtils.slugify(heading || "")
          s.empty? ? "heading" : s
        end

        # Backslash-escapes ASCII punctuation so link text stays literal.
        private def escape_text(text : String) : String
          String.build do |io|
            text.each_char do |c|
              io << '\\' if c.ascii? && !c.ascii_alphanumeric? && !c.ascii_whitespace?
              io << c
            end
          end
        end

        # Percent-encodes everything but unreserved characters and `/`, so a
        # path with spaces or parentheses is a valid Markdown destination.
        # The `@/` resolver decodes it back.
        private def encode(path : String) : String
          String.build do |io|
            path.each_byte do |b|
              c = b.unsafe_chr
              if c.ascii_alphanumeric? || c.in?('-', '.', '_', '~', '/')
                io << c
              else
                io << '%' << b.to_s(16, upcase: true).rjust(2, '0')
              end
            end
          end
        end

        # `walk`, with `$…$` / `$$…$$` math stashed out first when the math
        # pass is on.
        private def scan(content : String, math : Bool, re : Regex, & : Regex::MatchData -> String?) : String
          return walk(content, re) { |md| yield md } unless math && content.includes?('$')
          MarkdownExtensions.protect_math(content) { |stashed| walk(stashed, re) { |md| yield md } }
        end

        # The walk shared by `rewrite` and `each_link`. Fenced and indented
        # code and raw HTML block lines (FenceTracker) pass through; the rest
        # is matched one chunk at a time (lines up to a blank line or an ATX
        # heading, so a code span can cross a line break but not a
        # paragraph). Code/comment matches pass through; every other match
        # is replaced by the block's result (nil keeps it).
        private def walk(content : String, re : Regex, & : Regex::MatchData -> String?) : String
          tracker = FenceTracker.new
          chunk = String::Builder.new
          String.build(content.bytesize) do |io|
            content.each_line(chomp: false) do |line|
              verbatim = tracker.fence_line?(line) || tracker.html_block_line?
              heading = !verbatim && FenceTracker::ATX_HEADING_RE.matches?(line)
              if verbatim || heading || line.blank?
                unless chunk.empty?
                  io << transform(chunk.to_s, re) { |md| yield md }
                  chunk = String::Builder.new
                end
                io << (heading ? transform(line, re) { |md| yield md } : line)
              else
                chunk << line
              end
            end
            io << transform(chunk.to_s, re) { |md| yield md } unless chunk.empty?
          end
        end

        private def transform(text : String, re : Regex, & : Regex::MatchData -> String?) : String
          text.gsub(re) do |match|
            md = $~
            md["code"]? || md["comment"]? ? match : yield(md) || match
          end
        end
      end
    end
  end
end
