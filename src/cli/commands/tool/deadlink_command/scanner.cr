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
          # Markdown links inside fenced code blocks or inline code spans are
          # documentation examples (e.g. a `![Diagram](/images/diagram.png)`
          # snippet demonstrating image syntax), not real links. Strip them
          # before scanning so `check-links` doesn't report false-positive dead
          # links — mirrors the code-stripping the scaffold link-integrity spec
          # already performs.
          #
          # Fences are tracked line-by-line, CommonMark-style: a fence opens
          # with 3+ backticks/tildes (up to 3 spaces of indent) and only
          # closes on a fence of the same character at least as long. The old
          # non-greedy /```[\s\S]*?```/ mispaired nested fences — a 4-backtick
          # example wrapping a 3-backtick fence desynchronized every fence
          # after it, resurrecting example links as false positives.
          # Also stripped: HTML comments and indented (4-space/tab) code
          # blocks. Both hold example markup that is not a link — a
          # `<!-- <img src="/old.png"> -->` note and an indented
          # `<a href="/example/">` demo were each reported dead.
          #
          # Indented code is recognized conservatively, per CommonMark: a run
          # only counts as code when it follows a blank line AND no list item
          # is open. Without the list guard a 4-space list-item continuation
          # would be swallowed, which is exactly the failure that made the
          # sibling validator give up on indented blocks entirely.
          private def strip_code(content : String) : String
            result = String::Builder.new
            fence_char : Char? = nil
            fence_len = 0
            in_comment = false
            in_indented_code = false
            in_list = false
            prev_blank = true

            content.each_line(chomp: false) do |line|
              blank = line.strip.empty?

              # HTML comments span lines and can open/close mid-line.
              if in_comment
                if idx = line.index("-->")
                  in_comment = false
                  result << line[(idx + 3)..].gsub(/`[^`\n]*`/, "")
                else
                  result << '\n'
                end
                prev_blank = blank
                next
              end

              if m = line.match(/\A {0,3}(`{3,}|~{3,})/)
                marker = m[1]
                if fence_char.nil?
                  fence_char = marker[0]
                  fence_len = marker.size
                  in_indented_code = false
                  result << '\n'
                  prev_blank = false
                  next
                elsif marker[0] == fence_char && marker.size >= fence_len
                  fence_char = nil
                  fence_len = 0
                  result << '\n'
                  prev_blank = false
                  next
                end
              end

              if fence_char
                result << '\n'
                prev_blank = blank
                next
              end

              # Track list context so a 4-space continuation line is treated as
              # prose, not code.
              if line.matches?(/\A {0,3}(?:[-*+]|\d+[.)])\s/)
                in_list = true
              elsif blank
                # A blank line alone does not close a list; a subsequent
                # unindented non-list line does.
              elsif !line.starts_with?(" ") && !line.starts_with?("\t")
                in_list = false
              end

              indented = line.starts_with?("    ") || line.starts_with?("\t")
              if in_indented_code
                if blank || indented
                  result << '\n'
                  prev_blank = blank
                  next
                end
                in_indented_code = false
              elsif indented && prev_blank && !in_list && !blank
                in_indented_code = true
                result << '\n'
                prev_blank = false
                next
              end

              stripped = line.gsub(/`[^`\n]*`/, "")
              # A comment opened on this line: keep the text before it.
              if idx = stripped.index("<!--")
                if close = stripped.index("-->", idx)
                  stripped = stripped[0...idx] + stripped[(close + 3)..]
                else
                  in_comment = true
                  stripped = stripped[0...idx] + "\n"
                end
              end
              result << stripped
              prev_blank = blank
            end

            result.to_s
          end

          # Markdown link/image destinations share LINK_DEST +
          # clean_external_target with the internal scan, so titled
          # (`[x](https://url "t")`) and angle-bracket (`[x](<https://url>)`)
          # external destinations are checked too — the old regex required
          # `)` right after the URL and silently skipped both forms.
          # Raw HTML (`<a href="https://…">`, `<img src="https://…">`) is also
          # scanned here: the internal HTML pass drops scheme-carrying URLs
          # via skip_internal?, so without this pass they were never checked.
          private def find_external_links(dir : String) : Array(Link)
            links = [] of Link
            link_regex = /!?\[[^\]]*?\]\(#{LINK_DEST.source}\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = readable_markdown(file) || next
              content.scan(link_regex) do |match|
                url = clean_external_target(match[1])
                next unless external_url?(url)
                links << Link.new(file: file, url: url, kind: :external)
              end
              scan_reference_definitions(content) do |raw|
                url = clean_external_target(raw)
                next unless external_url?(url)
                links << Link.new(file: file, url: url, kind: :external)
              end
              content.scan(HTML_TAG_RE) do |tag|
                tag[2].scan(HTML_ATTR_RE) do |attr|
                  raw = attr[2]? || attr[3]? || attr[4]?
                  next unless raw
                  html_link_targets(attr[1], raw).each do |candidate|
                    url = clean_external_target(candidate)
                    next unless external_url?(url)
                    # Unrendered template syntax — same guard as the internal
                    # HTML pass; contacting the literal braces is never right.
                    next if url.includes?("{{") || url.includes?("{%")
                    links << Link.new(file: file, url: url, kind: :external)
                  end
                end
              end
            end
            links
          end

          private def external_url?(url : String) : Bool
            url.starts_with?("http://") || url.starts_with?("https://")
          end

          private def readable_markdown(file : String) : String?
            @scanned.fetch(file) { @scanned[file] = read_and_strip(file) }
          end

          private def read_and_strip(file : String) : String?
            strip_code(File.read(file))
          rescue ex : ArgumentError | IO::Error
            Logger.warn "Skipping #{file}: #{ex.message}"
            nil
          end

          # Markdown link/image destination, allowing ONE level of balanced
          # parentheses inside it. Plain `([^\)]+)` stopped at the first `)`,
          # so `[x](/docs/foo_(bar))` was scanned as `/docs/foo_(bar` and
          # reported dead — a false positive on a link the build resolves fine.
          # The alternation branches start with disjoint characters, so there
          # is no backtracking ambiguity.
          LINK_DEST = /((?:[^()]|\([^()]*\))*)/

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
          private def clean_link_target(raw : String) : String
            clean_external_target(raw).split("#").first.split("?").first.strip
          end

          # The external half of clean_link_target: strip the optional title
          # and unwrap an angle-bracket destination, but KEEP query string and
          # fragment — they are significant when contacting an external URL.
          private def clean_external_target(raw : String) : String
            stripped = raw.strip
            if stripped.starts_with?('<') && (close = stripped.index('>'))
              stripped[1...close]
            else
              stripped.split(/\s/, 2).first
            end
          end

          private def find_internal_links(dir : String) : Array(Link)
            links = [] of Link
            link_re = /(?<!!)\[([^\]]*)\]\(#{LINK_DEST.source}\)/
            image_re = /!\[([^\]]*)\]\(#{LINK_DEST.source}\)/

            Dir.glob("#{dir}/**/*.md").each do |file|
              content = readable_markdown(file) || next

              # Regular links (exclude images by using negative lookbehind)
              content.scan(link_re) do |match|
                url = clean_link_target(match[2])
                next if skip_internal?(url)
                links << Link.new(file: file, url: url, kind: :internal)
              end

              # Image links
              content.scan(image_re) do |match|
                url = clean_link_target(match[2])
                next if skip_internal?(url, allow_fragment: false)
                links << Link.new(file: file, url: url, kind: :image)
              end

              # Reference-style links (`[text][id]` + `[id]: /target/`) and
              # raw HTML anchors/images. Both render as real links, so a page
              # written that way used to get a clean bill of health.
              scan_reference_definitions(content) do |raw|
                url = clean_link_target(raw)
                next if skip_internal?(url)
                links << Link.new(file: file, url: url, kind: :internal)
              end

              content.scan(HTML_TAG_RE) do |tag|
                kind = tag[1].downcase == "a" ? :internal : :image
                tag[2].scan(HTML_ATTR_RE) do |attr|
                  raw = attr[2]? || attr[3]? || attr[4]?
                  next unless raw
                  html_link_targets(attr[1], raw).each do |candidate|
                    url = clean_link_target(candidate)
                    next if skip_internal?(url) || url.includes?("{{") || url.includes?("{%")
                    links << Link.new(file: file, url: url, kind: kind)
                  end
                end
              end
            end
            links
          end

          # `<a href>` / `<img src|srcset>` / `<source src|srcset>` written
          # directly in Markdown. `<source>` matters because `<picture>` and
          # `<video>` blocks are the common hand-written HTML in docs content.
          # The value may be unquoted (`href=/x/`), which stops at whitespace
          # or `>`.
          # Matched in two passes — tag, then each attribute inside it — because
          # a single regex consumes the whole tag and so only ever reports the
          # FIRST link attribute: `<img srcset="…" src="…">` lost its `src`.
          HTML_TAG_RE  = /<(a|img|source)\b([^>]*)>/i
          HTML_ATTR_RE = /\b(href|src|srcset)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i

          # One `srcset` entry is `url [descriptor]`, comma-separated.
          private def html_link_targets(attribute : String, value : String) : Array(String)
            return [value] unless attribute.downcase == "srcset"
            value.split(',').compact_map do |candidate|
              url = candidate.strip.split(/\s+/).first?
              url if url && !url.empty?
            end
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
              next unless dest.starts_with?('/') || dest.starts_with?("./") ||
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
