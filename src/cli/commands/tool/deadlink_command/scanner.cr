# check-links — Markdown scanning (code stripping, link and reference extraction).
#
# Reopens `Tool::DeadlinkCommand`; deadlink_command.cr keeps the flag
# metadata, the ivars and `run`. Parts only reopen the class: no requires, no
# load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module CLI
    module Commands
      module Tool
        class DeadlinkCommand
          # Markdown link/image destinations share LINK_DEST +
          # markdown_link_target with the internal scan, so titled
          # (`[x](https://url "t")`) and angle-bracket (`[x](<https://url>)`)
          # external destinations are checked too — the old regex required
          # `)` right after the URL and silently skipped both forms.
          # Raw HTML (`<a href="https://…">`, `<img src="https://…">`) is also
          # scanned here: the internal HTML pass drops scheme-carrying URLs
          # via skip_internal?, so without this pass they were never checked.
          private def find_external_links(dir : String) : Array(Link)
            links = [] of Link
            link_regex = /!?\[[^\]]*?\]\(#{LINK_DEST.source}\)/

            markdown_files(dir).each do |file|
              content = readable_markdown(file) || next
              content.scan(link_regex) do |match|
                url = normalize_external_url(markdown_link_target(match[1])) || next
                links << Link.new(file: file, url: url, kind: :external)
              end
              scan_reference_definitions(content) do |raw|
                url = normalize_external_url(markdown_link_target(raw)) || next
                links << Link.new(file: file, url: url, kind: :external)
              end
              # Inline-link and definition destinations may be written in
              # angle brackets too; those were already collected above.
              autolink_text(content.gsub(link_regex, "").gsub(REFERENCE_DEFINITION_RE, "")).scan(AUTOLINK_RE) do |match|
                # The scheme is case-insensitive (`<HTTPS://…>` is a link);
                # the HTTP client only speaks the lowercase form.
                links << Link.new(file: file, url: "#{match[2].downcase}#{match[3]}", kind: :external)
              end
              scan_html_link_targets(content) do |target, _|
                next if template_link_target?(target)
                url = normalize_external_url(target) || next
                links << Link.new(file: file, url: url, kind: :external)
              end
            end
            links
          end

          # A CommonMark autolink (`<https://example.com/x>`) renders as an
          # `<a href>` just like `[text](url)`, but neither the inline-link
          # pass nor the raw-HTML pass (which wants a tag name) saw it, so
          # an autolinked URL was never checked.
          #
          # An escaped `\<https://…>` (odd run of backslashes) is literal text.
          AUTOLINK_RE = /(?<!\\)(?:\\\\)*<((https?:\/\/)([^\s<>]*))>/i

          # A raw HTML block (a block opening with a block-level tag, or with
          # a line holding one complete tag) is passed through verbatim, so an
          # autolink-shaped `<https://…>` inside it is not a link.
          HTML_BLOCK_START_RE = /\A {0,3}(?:<\/?(?:address|article|aside|blockquote|body|center|details|dialog|dd|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|html|iframe|legend|li|main|menu|nav|ol|p|pre|script|section|style|summary|table|tbody|td|tfoot|th|thead|tr|ul)(?:[\s>\/]|\z)|<\/?[a-zA-Z][a-zA-Z0-9-]*(?:\s[^<>]*)?\/?>\s*$|<!--)/i

          # Remove raw HTML blocks and inline tags before scanning autolinks.
          # Autolink syntax inside a quoted tag attribute is plain text.
          private def autolink_text(content : String) : String
            content.split(/\n[ \t]*\n/).reject do |block|
              (first_line = block.lstrip('\n').each_line.first?) && first_line.chomp.matches?(HTML_BLOCK_START_RE)
            end.join("\n\n").gsub(HTML_TAG_RE, " ")
          end

          # The scheme is case-insensitive. Normalize only that part for the HTTP client.
          private def normalize_external_url(url : String) : String?
            return url if url.starts_with?("http://") || url.starts_with?("https://")
            if scheme = url.match(/\Ahttps?:\/\//i)
              scheme[0].downcase + scheme.post_match
            end
          end

          # Every Markdown source the build reads under `dir`: the shared
          # content walker matches extensions case-insensitively, as
          # ReadContent does, so `post.MD` and `post.MARKDOWN` are scanned too.
          private def markdown_files(dir : String) : Array(String)
            @markdown_files.fetch(dir) { @markdown_files[dir] = Services::ContentWalk.find_content_files(dir) }
          end

          private def readable_markdown(file : String) : String?
            @scanned.fetch(file) { @scanned[file] = read_and_strip(file) }
          end

          private def read_and_strip(file : String) : String?
            Utils::MarkdownCode.strip(File.read(file))
          rescue ex : ArgumentError | IO::Error
            Logger.warn "Skipping #{file}: #{ex.message}"
            nil
          end

          # Markdown link/image destination, allowing ONE level of balanced
          # parentheses inside it. Plain `([^\)]+)` stopped at the first `)`,
          # so `[x](/docs/foo_(bar))` was scanned as `/docs/foo_(bar` and
          # reported dead — a false positive on a link the build resolves fine.
          # The alternation branches start with disjoint characters, so there
          # is no backtracking ambiguity, and the loops are possessive: one
          # JIT frame per character aborted the whole command with "JIT
          # stack limit reached" on a ~60 KB data-URI image.
          LINK_DEST = /((?:[^()]++|\([^()]*+\))*+)/

          # Normalize a Markdown link/image destination to a bare URL.
          #
          # CommonMark allows an optional title after the destination
          # (`[t](/url "title")` / `![a](/img 'title')`); the capture includes
          # that title, so without stripping it the resolved target became e.g.
          # `/posts/b/ "title"` and every titled internal link was falsely
          # reported dead.
          #
          # An angle-bracket destination (`[t](</my page.md> "title")`) is the
          # one form that MAY contain spaces, so the whitespace split has to
          # come after unwrapping it — otherwise the target was the literal
          # `</my`, and even a space-free `</about/>` was reported dead while
          # the build resolved it correctly.
          # Keep queries and fragments for external checks and anchor tracking.
          private def markdown_link_target(raw : String) : String
            stripped = raw.strip
            if stripped.starts_with?('<') && (close = stripped.index('>'))
              stripped[1...close]
            else
              stripped.split(/\s/, 2).first
            end
          end

          private def internal_link_path(target : String) : String
            target.split(/[?#]/, 2).first.strip
          end

          # Remember an internal page link that carries a `#fragment`
          # (`#id`, `/x/#id`, `../x/#id`, `@/x.md#id`) for check_anchor_links.
          private def note_anchor_link(file : String, target : String, url : String) : Nil
            return if !url.empty? && skip_internal?(url)
            fragment = target.partition('#')[2]
            return if fragment.empty?
            @anchor_links << Link.new(file: file, url: "#{url}##{fragment}", kind: :anchor)
          end

          private def find_internal_links(dir : String) : Array(Link)
            links = [] of Link
            link_re = /(?<!!)\[([^\]]*)\]\(#{LINK_DEST.source}\)/
            image_re = /!\[([^\]]*)\]\(#{LINK_DEST.source}\)/

            markdown_files(dir).each do |file|
              content = readable_markdown(file) || next

              # Regular links (exclude images by using negative lookbehind)
              content.scan(link_re) do |match|
                target = markdown_link_target(match[2])
                url = internal_link_path(target)
                note_anchor_link(file, target, url)
                next if skip_internal?(url)
                links << Link.new(file: file, url: url, kind: :internal)
              end

              # Image links
              content.scan(image_re) do |match|
                url = internal_link_path(markdown_link_target(match[2]))
                next if skip_internal?(url, allow_fragment: false)
                links << Link.new(file: file, url: url, kind: :image)
              end

              # Reference-style links (`[text][id]` + `[id]: /target/`) and
              # raw HTML anchors/images. Both render as real links, so a page
              # written that way used to get a clean bill of health.
              scan_reference_definitions(content) do |raw|
                target = markdown_link_target(raw)
                url = internal_link_path(target)
                note_anchor_link(file, target, url)
                next if skip_internal?(url)
                links << Link.new(file: file, url: url, kind: :internal)
              end

              scan_html_link_targets(content) do |target, kind|
                url = internal_link_path(target)
                next if template_link_target?(url)
                note_anchor_link(file, target, url) if kind == :internal
                next if skip_internal?(url)
                links << Link.new(file: file, url: url, kind: kind)
              end
            end
            links
          end

          # Consume whole tags and attributes so quoted markup and names such
          # as `data-href` cannot be mistaken for links.
          HTML_TAG_RE  = /<([a-z][a-z0-9:_-]*)(?=[\s>]|\/>)(#{Utils::TextUtils::HTML_TAG_ATTRS_QUOTED_VALUES})>/i
          HTML_ATTR_RE = /([^\s\/="'<>]++)(?:\s*+=\s*+(?:"([^"]*+)"|'([^']*+)'|([^\s>]+)))?/

          private def scan_html_link_targets(content : String, &)
            content.scan(HTML_TAG_RE) do |tag|
              name = tag[1].downcase
              next unless name.in?("a", "img", "source")

              anchor = name == "a"
              kind = anchor ? :internal : :image
              seen = Set(String).new
              tag[2].scan(HTML_ATTR_RE) do |attr|
                attribute = attr[1].downcase
                next unless anchor ? attribute == "href" : attribute.in?("src", "srcset")
                next unless seen.add?(attribute)
                value = attr[2]? || attr[3]? || attr[4]? || next

                if attribute == "srcset"
                  Utils::TextUtils.srcset_url_spans(value).each do |start, stop|
                    yield value[start...stop], kind
                  end
                else
                  yield value.strip, kind
                end
              end
            end
          end

          private def template_link_target?(target : String) : Bool
            target.includes?("{{") || target.includes?("{%")
          end

          # A Markdown link reference definition (`[id]: /target/ "title"`).
          #
          # Three guards keep this from inventing links: footnote definitions
          # (`[^1]: …`) are skipped, the destination must look like a URL or
          # path, and — decisively — the label must actually be USED somewhere
          # in the document. Shape alone is not enough: the ordinary prose line
          #
          #     [Note]: /usr/bin is where the binary lives on most systems
          #
          # has a path-shaped first token and was reported as a dead link.
          # CommonMark only treats such a line as a definition when a matching
          # reference exists, so requiring one removes the whole false-positive
          # class rather than blacklisting shapes.
          REFERENCE_DEFINITION_RE = /^ {0,3}\[([^\]\n]+)\]:[ \t]*(\S+)/m

          # `[text][label]`, `[label][]`, and the shortcut form `[label]` — the
          # last excluding anything followed by `(`, `[` or `:`, which is an
          # inline link, a full reference, or another definition.
          REFERENCE_USE_RES = {
            /\]\[([^\]\n]+)\]/,
            /\[([^\]\n]+)\]\[\]/,
            /\[([^\]\n]+)\](?![\(\[:])/,
          }

          private def referenced_labels(content : String) : Set(String)
            labels = Set(String).new
            REFERENCE_USE_RES.each do |re|
              content.scan(re) { |m| labels << m[1].strip.downcase }
            end
            labels
          end

          private def scan_reference_definitions(content : String, &)
            used = referenced_labels(content)
            content.scan(REFERENCE_DEFINITION_RE) do |match|
              label = match[1]
              next if label.starts_with?('^')
              next unless used.includes?(label.strip.downcase)
              dest = match[2]
              dest = dest[1..-2] if dest.starts_with?('<') && dest.ends_with?('>')
              next unless dest.starts_with?('#') || dest.starts_with?('/') || dest.starts_with?("./") ||
                          dest.starts_with?("../") || dest.starts_with?("@/") ||
                          dest =~ /\A[a-z][a-z0-9+.\-]*:/i
              yield dest
            end
          end
        end
      end
    end
  end
end
