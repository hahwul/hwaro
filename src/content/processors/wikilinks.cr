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
require "./table_parser"
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
        # tag (Markd's grammar, so attribute values are never rewritten), an
        # autolink (`<https://x/[[y]]>`) and a backslash escape (`\[[x]]`
        # stays literal).
        VERBATIM_TOKENS = [
          /(?<code>`+)(?s:.*?)(?<!`)\k<code>(?!`)/.source,
          /(?<comment><!--(?s:.*?)-->)/.source,
          "(?<tag>#{MarkdownExtensions::HTML_TAG_RE.source})",
          /(?<autolink><[A-Za-z][A-Za-z0-9+.-]*:[^\s<>]*>)/.source,
        ].join('|')
        ESC_TOKEN = /(?<esc>\\[^\n])/.source
        # `\(…\)` TeX math, kept verbatim with `[markdown] math` (the `$`
        # forms are stashed by MarkdownExtensions.protect_math). Precedes
        # ESC_TOKEN, which would otherwise take its `\(`.
        TEX_TOKEN      = /(?<tex>\\\((?s:.*?)\\\))/.source
        WIKILINK_TOKEN = /(?<bang>!?)\[\[(?<inner>[^\[\]\n]+)\]\]/.source
        # The other link forms backlinks count: a Markdown destination
        # (`](url`, which `rewrite` also keeps verbatim, so a `[[x]]` inside
        # a URL is never rewritten) and a link reference definition
        # (`[label]: url`, not a footnote). HTML `href`s are read out of the
        # `tag` token.
        URL_TOKEN = /\]\(\s*<?(?<url>[^\s)>]+)/.source
        DEF_TOKEN = /(?m:^) {0,3}\[(?!\^)[^\]\n]+\]:[ \t]*<?(?<def>[^\s>]+)/.source
        HREF_RE   = /\bhref\s*=\s*["']([^"']*)["']/i

        LINK_TOKEN_RE      = Regex.new("#{VERBATIM_TOKENS}|#{ESC_TOKEN}|#{WIKILINK_TOKEN}|#{URL_TOKEN}|#{DEF_TOKEN}")
        LINK_MATH_TOKEN_RE = Regex.new("#{VERBATIM_TOKENS}|#{TEX_TOKEN}|#{ESC_TOKEN}|#{WIKILINK_TOKEN}|#{URL_TOKEN}|#{DEF_TOKEN}")

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
          # Never a file name or URL: Crystal's File API rejects NUL.
          return if inner.includes?('\0')
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
          scan(content, math, math ? LINK_MATH_TOKEN_RE : LINK_TOKEN_RE) do |md, sources, inline|
            next unless inner = md["inner"]?
            # `[[foo|cost $x$]]`: the math inside is the link's own text.
            next unless link = parse(MarkdownExtensions.restore_math(inner, sources), md["bang"] == "!")
            render(link, MarkdownExtensions.restore_math(md[0], sources), source, index, safe, misses, warn, math, inline)
          end
        end

        # Yields every link-ish token where `rewrite` would see one: a parsed
        # wikilink, or the URL of a Markdown destination / link reference
        # definition / HTML href. Hrefs in raw HTML blocks count too (the
        # build renders them as links), though `rewrite` leaves those lines
        # alone.
        def each_link(content : String, math : Bool = false, & : Link | String ->) : Nil
          return unless Utils::ByteScan.includes?(content, "[[") || Utils::ByteScan.includes?(content, "](") ||
                        Utils::ByteScan.includes?(content, "]:") || Utils::ByteScan.includes?(content, "href")
          scan(content, math, math ? LINK_MATH_TOKEN_RE : LINK_TOKEN_RE) do |md, sources|
            if inner = md["inner"]?
              parse(MarkdownExtensions.restore_math(inner, sources), md["bang"] == "!").try { |link| yield link }
            elsif url = md["url"]? || md["def"]?
              yield MarkdownExtensions.restore_math(url, sources)
            elsif tag = md["tag"]?
              MarkdownExtensions.restore_math(tag, sources).scan(HREF_RE) { |m| yield m[1] }
            end
            nil
          end
          return unless Utils::ByteScan.includes?(content, "href")
          tracker = FenceTracker.new
          in_comment = false
          content.each_line(chomp: false) do |line|
            next if tracker.fence_line?(line) || !tracker.html_block_line?
            # Not inside an HTML comment, which renders no link.
            if in_comment
              close = line.index("-->") || next
              line = line[(close + 3)..]
              in_comment = false
            end
            line = line.gsub(/<!--.*?-->/, "")
            if open = line.index("<!--")
              line = line[0, open]
              in_comment = true
            end
            line.scan(HREF_RE) { |m| yield m[1] }
          end
        end

        # `inline`: the text lands in a table cell, a definition list or a
        # footnote body, which InlineMarkdown renders. It has no backslash
        # escapes, raw HTML or image attribute blocks, so there the link
        # text is written as is, a missing link is plain text, and the
        # size block is one it understands.
        private def render(link : Link, source_text : String, source : Models::Page, index : Index, safe : Bool,
                           misses : Array({String, String})?, warn : Bool, math : Bool, inline : Bool) : String
          if link.image?
            if url = index.resolve_file(link.target, source)
              return image(link, url, inline)
            end
          elsif link.target.empty?
            return "[#{text(link.text, inline)}](##{encode(slug(link.heading))})"
          elsif page = index.resolve(link.target, source)
            dest = "@/#{encode(page.path)}"
            dest += "##{encode(slug(link.heading))}" if link.heading
            return "[#{text(link.text, inline)}](#{dest})"
          elsif link.file? && (url = index.resolve_file(link.target, source))
            # An attachment (`[[doc.pdf]]`, `![[doc.pdf]]`): a plain link.
            return "[#{text(link.text, inline)}](#{encode(url)})"
          end

          reason = link.file? ? "file not found" : "page not found"
          Logger.warn "Wikilink '#{source_text}' in '#{source.path}' could not be resolved: #{reason}." if warn
          misses << {source_text, reason} if misses
          return text(link.text, inline) if safe || inline
          body = math && link.text.includes?('$') ? MarkdownExtensions.protect_math(link.text) { |stashed, _| escape_span_text(stashed) } : escape_span_text(link.text)
          %(<span class="wikilink wikilink-missing">#{body}</span>)
        end

        # `|300` / `|300x200` sizes the image through an attribute block
        # (MarkdownExtensions enables image attributes with wikilinks); any
        # other alias is the alt text, which otherwise is the file name.
        private def image(link : Link, url : String, inline : Bool) : String
          label = link.label
          size = label.try(&.match(SIZE_RE))
          alt = label && !size ? label : File.basename(link.target)
          String.build do |io|
            io << "![" << text(alt, inline) << "](" << encode(url) << ')'
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

        # Link text as the target context reads it (see `render`).
        private def text(text : String, inline : Bool) : String
          inline ? text : escape_text(text)
        end

        # The text of a missing-link `<span>`, which Markd still reads for
        # emphasis, code spans and backslash escapes between the tags (a
        # trailing `\` would swallow the `<` of `</span>`): HTML-escaped,
        # with those Markdown characters backslash-escaped.
        private def escape_span_text(text : String) : String
          HTML.escape(text).gsub(/[\\*_`\[\]~]/) { |char| "\\#{char}" }
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
        # The block also gets the stashed math sources (empty without math),
        # for `MarkdownExtensions.restore_math` on what it lifts out.
        private def scan(content : String, math : Bool, re : Regex, & : Regex::MatchData, Array(String), Bool -> String?) : String
          none = [] of String
          return walk(content, re) { |md, inline| yield md, none, inline } unless math && content.includes?('$')
          MarkdownExtensions.protect_math(content) do |stashed, sources|
            walk(stashed, re) { |md, inline| yield md, sources, inline }
          end
        end

        # A line matched on its own, never joined to a chunk: an ATX heading,
        # a setext underline or thematic break. Table rows are too (see
        # `walk`), each row being its own block.
        STANDALONE_LINE_RE = /\A(?: {0,3}>[ \t]?)*(?: {0,3}\#{1,6}(?:[ \t]|\r?\n?\z)| {0,3}(?:=+|-+|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})[ \t]*\r?\n?\z)/
        # One blockquote marker, as TableParser strips it for a quoted table.
        QUOTE_PREFIX_RE = /\A {0,3}> ?/
        # A footnote definition starts a new block, as a list item does. Same
        # shape preprocess_footnotes extracts (`FOOTNOTE_DEF_RE` there).
        FOOTNOTE_DEF_RE = /\A\[\^[^\]]+\]:[^\n]/
        # The blockquote markers a line opens with.
        QUOTE_MARKERS_RE = /\A(?: {0,3}>[ \t]?)*/

        # The walk shared by `rewrite` and `each_link`. Fenced and indented
        # code and raw HTML block lines (FenceTracker) pass through; the rest
        # is matched one chunk at a time: the lines of one paragraph or list
        # item (a chunk ends at a blank line and before a list marker or a
        # footnote definition, after a definition at the first line its parser
        # does not continue it with (anything not indented by a tab or four
        # spaces), and before a line quoted deeper than the chunk began;
        # STANDALONE_LINE_RE lines and the rows of a table TableParser would
        # build are chunks of their own), so a code span can cross a line
        # break but not a block.
        # Code/comment matches pass through; every other match is replaced
        # by the block's result (nil keeps it). The block also learns whether
        # the match sits where InlineMarkdown, not Markd, renders it: a table
        # row, a footnote body, or a chunk holding a `: definition` line
        # (assumed to be a definition list).
        private def walk(content : String, re : Regex, & : Regex::MatchData, Bool -> String?) : String
          tracker = FenceTracker.new
          chunk = String::Builder.new
          lines = content.lines(chomp: false)
          in_table = false
          in_footnote = false
          chunk_inline = false
          chunk_quote = 0
          String.build(content.bytesize) do |io|
            lines.each_with_index do |line, i|
              verbatim = tracker.fence_line?(line) || tracker.html_block_line?
              in_table = !verbatim && table_line?(line, lines[i + 1]?, in_table)
              standalone = !verbatim && (in_table || STANDALONE_LINE_RE.matches?(line))
              blank = line.blank?
              footnote = FOOTNOTE_DEF_RE.matches?(line)
              indented = line.starts_with?("    ") || line.starts_with?('\t')
              quote = QUOTE_MARKERS_RE.match(line).try(&.[0].count('>')) || 0
              if verbatim || standalone || blank || tracker.list_item_line? || footnote ||
                 (in_footnote && !indented) || (!chunk.empty? && quote > chunk_quote)
                unless chunk.empty?
                  io << transform(chunk.to_s, re) { |md| yield md, chunk_inline }
                  chunk = String::Builder.new
                end
              end
              in_footnote = footnote || (in_footnote && (blank || indented))
              if verbatim || blank
                io << line
              elsif standalone
                io << transform(line, re) { |md| yield md, in_table }
              else
                if chunk.empty?
                  chunk_quote = quote
                  chunk_inline = in_footnote
                end
                chunk_inline ||= line.lstrip.starts_with?(": ")
                chunk << line
              end
            end
            io << transform(chunk.to_s, re) { |md| yield md, chunk_inline } unless chunk.empty?
          end
        end

        # Whether `line` is a row of a table TableParser converts: a header
        # whose next line is a delimiter row, or a piped row after one.
        private def table_line?(line : String, following : String?, in_table : Bool) : Bool
          return false unless line.includes?('|')
          row = line.sub(QUOTE_PREFIX_RE, "")
          return TableParser.table_row?(row) if in_table
          !following.nil? && TableParser.table_row?(row) && TableParser.separator_row?(following.sub(QUOTE_PREFIX_RE, ""))
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
