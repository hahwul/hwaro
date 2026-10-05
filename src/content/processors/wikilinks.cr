# Obsidian-style `[[wikilinks]]` and `![[embeds]]` (`[markdown] wikilinks`).
#
# The rewrite runs on the page's Markdown after shortcode expansion and
# before Markd: a resolved link becomes an ordinary `[text](@/path.md#slug)`
# link and an image embed an ordinary `![alt](url)` image, so the `@/`
# resolver, render hooks, `base_path`, the external-link policy and the
# `[links]` checks all apply unchanged. Nothing is rewritten inside fenced or
# indented code (FenceTracker), inline code spans or HTML comments (which
# also covers shortcode placeholders).

require "html"
require "./fence_tracker"
require "../../models/page"
require "../../utils/byte_scan"
require "../../utils/logger"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Processors
      module Wikilinks
        extend self

        # One prose token per match: an inline code span or an HTML comment
        # (both kept verbatim; an unclosed comment runs to the end of the
        # line and on until `-->`), or a `[[…]]` / `![[…]]` wikilink.
        WIKILINK_TOKEN_RE = /(?<code>`+).*?(?<!`)\k<code>(?!`)|(?<comment><!--.*?(?:-->|$))|(?<bang>!?)\[\[(?<inner>[^\[\]\n]+)\]\]/

        # WIKILINK_TOKEN_RE plus the other link forms backlinks count: a
        # Markdown destination (`](url)`) and an HTML `href`.
        LINK_TOKEN_RE = /(?<code>`+).*?(?<!`)\k<code>(?!`)|(?<comment><!--.*?(?:-->|$))|(?<bang>!?)\[\[(?<inner>[^\[\]\n]+)\]\]|\]\(\s*<?(?<url>[^\s)>]+)|\bhref\s*=\s*["'](?<href>[^"']*)["']/

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

        # Page and file lookup for one page set. Read-only after construction
        # except for the warn-once set and the lazily built file index, both
        # behind the mutex (render workers share one index).
        class Index
          @by_name = {} of String => Array(Models::Page)
          @by_path = {} of String => Array(Models::Page)
          @warned = Set({String, String}).new
          @files : Hash(String, Array({String, String}))? = nil
          @mutex = Mutex.new

          # `files` lists every published non-page file as
          # `{relative path, URL}`; it is only called on the first embed
          # that is not one of the source page's own bundle assets.
          def initialize(pages : Enumerable(Models::Page), default_language : String,
                         @files_source : Proc(Array({String, String})) = -> { [] of {String, String} })
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
              {File.basename(dir).downcase, dir.downcase}
            else
              {stem.downcase, (dir.empty? ? stem : "#{dir}/#{stem}").downcase}
            end
          end

          def resolve(target : String, source : Models::Page) : Models::Page?
            key = target.strip.lchop('/').rchop('/').downcase.rchop(".markdown").rchop(".md")
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
            want = target.strip.lchop('/').downcase
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
            low = rel.downcase
            want.includes?('/') ? low == want || low.ends_with?("/#{want}") : File.basename(low) == want
          end

          private def index_files : Hash(String, Array({String, String}))
            map = {} of String => Array({String, String})
            @files_source.call.each do |entry|
              (map[File.basename(entry[0]).downcase] ||= [] of {String, String}) << entry
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
            first = @mutex.synchronize { @warned.add?({source.path, target}) }
            if first
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
                    misses : Array({String, String})? = nil, warn : Bool = true) : String
          return content unless Utils::ByteScan.includes?(content, "[[")
          walk(content, WIKILINK_TOKEN_RE) do |md|
            next unless link = parse(md["inner"], md["bang"] == "!")
            render(link, md[0], source, index, safe, misses, warn)
          end
        end

        # Yields every link-ish token outside code and comments: a parsed
        # wikilink, or the URL of a Markdown destination / HTML href.
        def each_link(content : String, & : Link | String ->) : Nil
          return unless Utils::ByteScan.includes?(content, "[[") || Utils::ByteScan.includes?(content, "](") ||
                        Utils::ByteScan.includes?(content, "href")
          walk(content, LINK_TOKEN_RE) do |md|
            if inner = md["inner"]?
              parse(inner, md["bang"] == "!").try { |link| yield link }
            elsif url = md["url"]? || md["href"]?
              yield url
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
          end

          reason = link.image? ? "file not found" : "page not found"
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

        # The fence- and comment-aware line walk shared by `rewrite` and
        # `each_link`: `re`'s `code`/`comment` matches pass through, every
        # other match is replaced by the block's result (nil keeps it).
        private def walk(content : String, re : Regex, & : Regex::MatchData -> String?) : String
          tracker = FenceTracker.new
          in_comment = false
          String.build(content.bytesize) do |io|
            content.each_line(chomp: false) do |line|
              if tracker.fence_line?(line)
                io << line
                next
              end
              if in_comment
                unless close = line.index("-->")
                  io << line
                  next
                end
                io << line[0, close + 3]
                line = line[(close + 3)..]
                in_comment = false
              end
              io << line.gsub(re) do |match|
                md = $~
                if md["code"]?
                  match
                elsif comment = md["comment"]?
                  in_comment = !comment.ends_with?("-->")
                  match
                else
                  yield(md) || match
                end
              end
            end
          end
        end
      end
    end
  end
end
