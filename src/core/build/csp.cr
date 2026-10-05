# `[csp]` — a Content-Security-Policy per emitted HTML page.
#
# Runs once per build, after every other output transform (minify, the
# `[privacy]` rewrite, AMP, the PWA tags, taxonomy pages, the Finalize
# prune): it walks the HTML the build left in the output directory, hashes
# each page's inline `<script>`/`<style>` bodies and `style="…"` attributes
# exactly as the browser will see them, and emits the policy as a `<meta>`
# tag in the page or as a per-path rule in a `_headers` file. Reading the
# final files rather than hooking every writer means a `--cache` hit (whose
# render was skipped) is hashed from the same bytes a cold build wrote.
#
# Never runs under `hwaro serve`: the live-reload client and the error
# overlay are inline and dev-only.

require "base64"
require "openssl"

module Hwaro
  module Core
    module Build
      module Csp
        # What one page needs from the policy.
        record Scan,
          scripts : Array(String),
          styles : Array(String),
          style_attrs : Array(String),
          handlers : Bool

        # The outcome of one build's pass: page file → the policy it got,
        # under the output directory `root`.
        record Result, root : String, policies : Hash(String, String)

        # One page's share of the pass, computed on a worker fiber.
        record PageResult, path : String, relative : String, policy : String, handlers : Bool, headless : Bool

        # Sources a feature Hwaro itself emits needs, keyed by markers the
        # feature leaves in the page: its URL, and for an embed whose script
        # `[privacy]` can localize while it still loads more from its host,
        # the shortcode's own markup. A page gets a row's sources only when
        # its final HTML contains a marker, so a CDN that `[privacy]` fully
        # localized, or a shortcode the page does not use, adds nothing.
        FEATURE_SOURCES = [
          {markers: ["https://cdnjs.cloudflare.com/ajax/libs/highlight.js/"], sources: {"script-src" => "https://cdnjs.cloudflare.com", "style-src" => "https://cdnjs.cloudflare.com"}},
          {markers: ["https://cdn.jsdelivr.net/npm/katex@"], sources: {"script-src" => "https://cdn.jsdelivr.net", "style-src" => "https://cdn.jsdelivr.net", "font-src" => "https://cdn.jsdelivr.net"}},
          {markers: ["https://cdn.jsdelivr.net/npm/mathjax@"], sources: {"script-src" => "https://cdn.jsdelivr.net", "font-src" => "https://cdn.jsdelivr.net"}},
          {markers: ["https://cdn.jsdelivr.net/npm/mermaid@"], sources: {"script-src" => "https://cdn.jsdelivr.net"}},
          {markers: ["https://www.youtube.com/embed/"], sources: {"frame-src" => "https://www.youtube.com"}},
          {markers: ["https://player.vimeo.com/video/"], sources: {"frame-src" => "https://player.vimeo.com"}},
          {markers: ["https://gist.github.com/", %(class="sc-gist")], sources: {"script-src" => "https://gist.github.com", "style-src" => "https://github.githubassets.com"}},
          {markers: ["https://platform.twitter.com/widgets.js", %(class="twitter-tweet")], sources: {"script-src" => "https://platform.twitter.com", "frame-src" => "https://platform.twitter.com"}},
          {markers: ["https://codepen.io/"], sources: {"frame-src" => "https://codepen.io"}},
        ]

        # Header lines longer than this are dropped by Cloudflare Pages.
        CLOUDFLARE_HEADER_LIMIT = 2000

        # `<script type>` values the browser executes (and so checks against
        # `script-src`): the JavaScript MIME types, `module`, and the two
        # inline-only JSON types the HTML spec runs through CSP. Every other
        # type (`application/ld+json`, `text/template`, …) is a data block.
        EXECUTED_SCRIPT_TYPES = %w[
          module importmap speculationrules
          application/ecmascript application/javascript application/x-ecmascript
          application/x-javascript text/ecmascript text/javascript text/javascript1.0
          text/javascript1.1 text/javascript1.2 text/javascript1.3 text/javascript1.4
          text/javascript1.5 text/jscript text/livescript text/x-ecmascript text/x-javascript
        ]

        # Elements whose content the parser does not read as markup, skipped
        # without hashing. Not `<noscript>`: with scripting off its content
        # is markup, and a `<style>` in it is checked against the policy.
        OPAQUE_ELEMENTS = %w[textarea title xmp iframe noembed noframes]
        TEXT_ELEMENTS   = %w[script style] + OPAQUE_ELEMENTS

        # Directives a `<meta>` policy cannot carry (CSP3 §6.1).
        META_IGNORED = %w[frame-ancestors report-uri sandbox]

        # Rules beyond which Cloudflare Pages stops reading a `_headers` file.
        CLOUDFLARE_RULE_LIMIT = 100

        META_PREFIX = %(<meta http-equiv="Content-Security-Policy" content=")

        # --- scanning -------------------------------------------------------

        def self.scan(html : String) : Scan
          bytes = html.to_slice
          scripts = [] of String
          styles = [] of String
          style_attrs = [] of String
          handlers = false
          i = 0
          n = bytes.size
          loop do
            break unless lt = bytes_index(bytes, '<'.ord.to_u8, i)
            i = lt + 1
            break if i >= n
            if starts_with?(bytes, lt, "<!--")
              i = comment_end(bytes, lt)
              next
            end
            # An end tag, `<!DOCTYPE>`, `<?…>` or a stray `<`.
            next unless ascii_letter?(bytes[i])
            name_end = i
            while name_end < n && !tag_name_end?(bytes[name_end])
              name_end += 1
            end
            attrs, tag_end = parse_attributes(bytes, name_end)
            attrs.each do |attr|
              if attr_named?(bytes, attr, "style")
                value = attr_value(bytes, attr)
                style_attrs << hash(decode_attribute(value)) if value
              elsif attr[1] > 2 && name_at?(bytes, attr[0], "on")
                handlers = true
              end
            end
            i = tag_end
            name = TEXT_ELEMENTS.find { |e| e.bytesize == name_end - lt - 1 && name_at?(bytes, lt + 1, e) }
            next unless name
            close = find_end_tag(bytes, name, i) || n
            if name == "script"
              scripts << hash(String.new(bytes[i, close - i])) if executed_inline_script?(bytes, attrs)
            elsif name == "style"
              styles << hash(String.new(bytes[i, close - i]))
            end
            i = close
          end
          Scan.new(scripts.uniq, styles.uniq, style_attrs.uniq, handlers)
        end

        # `'sha256-…'` of `body` as the browser hashes it: after the input
        # stream's newline normalization (CRLF and lone CR become LF).
        def self.hash(body : String) : String
          body = body.gsub("\r\n", "\n").tr("\r", "\n") if body.includes?('\r')
          "'sha256-#{Base64.strict_encode(OpenSSL::Digest.new("SHA256").update(body).final)}'"
        end

        private def self.executed_inline_script?(bytes : Bytes, attrs : Array(Attr)) : Bool
          return false if attrs.any? { |attr| attr_named?(bytes, attr, "src") }
          return true unless type_attr = attrs.find { |attr| attr_named?(bytes, attr, "type") }
          type = (attr_value(bytes, type_attr) || "").strip.downcase
          type.empty? || EXECUTED_SCRIPT_TYPES.includes?(type)
        end

        # An attribute value as the HTML parser decodes it: a named reference
        # without `;` stays literal when `=` or an alphanumeric follows it
        # (`url(a?x=1&copy=2)` keeps its `&copy`), which `HTML.unescape`
        # alone would decode.
        def self.decode_attribute(raw : String) : String
          return raw unless raw.includes?('&') && raw.valid_encoding?
          raw.gsub(/&(?:#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[a-zA-Z][a-zA-Z0-9]*;?)/) do |ref, match|
            if ref.ends_with?(';') || ref.byte_at(1) == '#'.ord
              HTML.unescape(ref)
            elsif match.post_match.starts_with?('=')
              ref
            else
              decoded = HTML.unescape(ref)
              decoded == HTML.unescape("#{ref};") ? decoded : ref
            end
          end
        end

        # Offset just past the comment that opens at `lt`, as the tokenizer
        # ends it: `<!-->` and `<!--->` close at once, otherwise the first
        # `-->` or `--!>` does (or the end of the document).
        private def self.comment_end(bytes : Bytes, lt : Int32) : Int32
          j = lt + 4
          return j + 1 if j < bytes.size && bytes[j] == '>'.ord
          return j + 2 if starts_with?(bytes, j, "->")
          while dash = find(bytes, "--", j)
            k = dash + 2
            return k + 1 if k < bytes.size && bytes[k] == '>'.ord
            return k + 2 if starts_with?(bytes, k, "!>")
            j = dash + 1
          end
          bytes.size
        end

        # One attribute as byte offsets: name start, name length, value
        # start (-1 when valueless) and value length.
        alias Attr = {Int32, Int32, Int32, Int32}

        private def self.attr_named?(bytes : Bytes, attr : Attr, name : String) : Bool
          attr[1] == name.bytesize && name_at?(bytes, attr[0], name)
        end

        private def self.attr_value(bytes : Bytes, attr : Attr) : String?
          String.new(bytes[attr[2], attr[3]]) if attr[2] >= 0
        end

        # Attributes of the tag whose name ends at `pos`, and the offset just
        # past its `>`. Byte ranges only: this runs on every tag of every page.
        private def self.parse_attributes(bytes : Bytes, pos : Int32) : {Array(Attr), Int32}
          attrs = [] of Attr
          n = bytes.size
          i = pos
          loop do
            while i < n && (space?(bytes[i]) || bytes[i] == '/'.ord)
              i += 1
            end
            return {attrs, n} if i >= n
            return {attrs, i + 1} if bytes[i] == '>'.ord
            start = i
            while i < n && !space?(bytes[i]) && !bytes[i].in?('/'.ord, '>'.ord, '='.ord)
              i += 1
            end
            # A lone `=` (malformed) is consumed as a one-byte name.
            i += 1 if i == start
            j = i
            while j < n && space?(bytes[j])
              j += 1
            end
            if j < n && bytes[j] == '='.ord
              j += 1
              while j < n && space?(bytes[j])
                j += 1
              end
              if j < n && bytes[j].in?('"'.ord, '\''.ord)
                close = bytes_index(bytes, bytes[j], j + 1) || n
                attrs << {start, i - start, j + 1, close - j - 1}
                i = Math.min(close + 1, n)
              else
                v = j
                while j < n && !space?(bytes[j]) && bytes[j] != '>'.ord
                  j += 1
                end
                attrs << {start, i - start, v, j - v}
                i = j
              end
            else
              attrs << {start, i - start, -1, 0}
            end
          end
        end

        # Offset of the `</name` that closes a raw-text element, matched
        # ASCII case-insensitively and followed by a tag-name terminator.
        private def self.find_end_tag(bytes : Bytes, name : String, from : Int32) : Int32?
          i = from
          while lt = bytes_index(bytes, '<'.ord.to_u8, i)
            j = lt + 2 + name.bytesize
            if j <= bytes.size && bytes[lt + 1] == '/'.ord && name_at?(bytes, lt + 2, name) && (j == bytes.size || tag_name_end?(bytes[j]))
              return lt
            end
            i = lt + 1
          end
        end

        private def self.name_at?(bytes : Bytes, pos : Int32, name : String) : Bool
          return false if pos + name.bytesize > bytes.size
          name.each_byte.with_index.all? { |b, k| bytes[pos + k] | 0x20 == b }
        end

        private def self.starts_with?(bytes : Bytes, pos : Int32, prefix : String) : Bool
          pos + prefix.bytesize <= bytes.size && bytes[pos, prefix.bytesize] == prefix.to_slice
        end

        private def self.find(bytes : Bytes, needle : String, from : Int32) : Int32?
          first = needle.byte_at(0)
          i = from
          while hit = bytes_index(bytes, first, i)
            return hit if starts_with?(bytes, hit, needle)
            i = hit + 1
          end
        end

        private def self.bytes_index(bytes : Bytes, byte : UInt8, from : Int32) : Int32?
          from < bytes.size ? bytes.index(byte, from) : nil
        end

        private def self.ascii_letter?(b : UInt8) : Bool
          (b | 0x20).in?('a'.ord..'z'.ord)
        end

        private def self.space?(b : UInt8) : Bool
          b.in?(' '.ord, '\t'.ord, '\n'.ord, '\r'.ord, '\f'.ord)
        end

        private def self.tag_name_end?(b : UInt8) : Bool
          space?(b) || b == '/'.ord || b == '>'.ord
        end

        # --- policy ---------------------------------------------------------

        # The policy for one page. `meta` drops what a `<meta>` cannot carry.
        def self.policy(config : Models::CspConfig, html : String, scan : Scan = scan(html), meta : Bool = config.meta?) : String
          dirs = Models::CspConfig::DEFAULT_DIRECTIVES.dup
          config.directives.each do |name, value|
            # Empty removes a default; otherwise it is a valueless directive
            # such as `upgrade-insecure-requests`.
            value.empty? && dirs.has_key?(name) ? dirs.delete(name) : (dirs[name] = value)
          end
          FEATURE_SOURCES.each do |row|
            next unless row[:markers].any? { |marker| Utils::ByteScan.includes?(html, marker) }
            row[:sources].each { |directive, source| add_source(dirs, directive, source) }
          end
          add_hashes(dirs, "script-src", scan.scripts)
          add_hashes(dirs, "script-src-elem", scan.scripts) if dirs.has_key?("script-src-elem")
          add_hashes(dirs, "style-src", scan.styles)
          add_hashes(dirs, "style-src-elem", scan.styles) if dirs.has_key?("style-src-elem")
          unless scan.style_attrs.empty? || unsafe_inline?(dirs["style-src-attr"]? || dirs["style-src"]? || dirs["default-src"]?)
            dirs["style-src-attr"] = "" unless dirs.has_key?("style-src-attr")
            add_source(dirs, "style-src-attr", "'unsafe-hashes'")
            scan.style_attrs.each { |h| add_source(dirs, "style-src-attr", h) }
          end
          META_IGNORED.each { |name| dirs.delete(name) } if meta
          dirs.join("; ") { |name, value| value.empty? ? name : "#{name} #{value}" }
        end

        # Hashes go into `directive` unless the user opted out with
        # `'unsafe-inline'`, which browsers ignore as soon as a hash is listed.
        private def self.add_hashes(dirs : Hash(String, String), directive : String, hashes : Array(String)) : Nil
          return if unsafe_inline?(dirs[directive]? || fallback_value(dirs, directive))
          hashes.each { |h| add_source(dirs, directive, h) }
        end

        private def self.unsafe_inline?(value : String?) : Bool
          !!value.try(&.split.includes?("'unsafe-inline'"))
        end

        # Add `source` to `directive`. An absent directive starts from what
        # the browser would have fallen back to, so adding a frame host does
        # not silently drop `'self'`; `'none'` gives way to any source.
        private def self.add_source(dirs : Hash(String, String), directive : String, source : String) : Nil
          current = dirs[directive]? || fallback_value(dirs, directive)
          tokens = current.split
          return if tokens.includes?(source)
          tokens.delete("'none'")
          tokens << source
          dirs[directive] = tokens.join(" ")
        end

        private def self.fallback_value(dirs : Hash(String, String), directive : String) : String
          case directive
          when "frame-src"         then dirs["child-src"]? || dirs["default-src"]? || ""
          when "script-src-elem"   then dirs["script-src"]? || dirs["default-src"]? || ""
          when "style-src-elem"    then dirs["style-src"]? || dirs["default-src"]? || ""
          when .ends_with?("-src") then dirs["default-src"]? || ""
          else                          ""
          end
        end

        # --- emission -------------------------------------------------------

        # `html` with its policy `<meta>` as the first child of `<head>` —
        # after a leading `<meta charset>`, which must stay within the first
        # 1024 bytes. A meta a previous build injected is replaced. Unchanged
        # when the page has no `<head>`.
        def self.inject_meta(html : String, policy : String) : String
          return html unless at = meta_position(html)
          rest = own_meta_end(html, at) || at
          String.build(html.bytesize + policy.bytesize + 64) do |io|
            io.write(html.to_slice[0, at])
            io << META_PREFIX << Utils::TextUtils.escape_xml(policy) << %(">)
            io.write(html.to_slice[rest, html.bytesize - rest])
          end
        end

        # `html` without the policy `<meta>` a previous build injected. Hwaro
        # reads a `--cache` hit's HTML back from disk before Finalize (the
        # AMP converter, the PWA cache name); stripping it there keeps those
        # outputs identical to a cold build's.
        def self.strip_meta(html : String) : String
          return html unless (at = meta_position(html)) && (close = own_meta_end(html, at))
          html.byte_slice(0, at) + html.byte_slice(close, html.bytesize - close)
        end

        # The end of an injected policy `<meta>` starting at `at`, if any.
        private def self.own_meta_end(html : String, at : Int32) : Int32?
          return unless starts_with?(html.to_slice, at, META_PREFIX)
          Utils::ByteScan.byte_index(html, %(">), at + META_PREFIX.bytesize).try(&.+(2))
        end

        # Where the policy `<meta>` goes: just inside `<head>`, or just after
        # a charset declaration that only `<title>` and other `<meta>` tags
        # precede, so the declaration stays within the first 1024 bytes.
        # Nil without a `<head>` tag.
        private def self.meta_position(html : String) : Int32?
          bytes = html.to_slice
          return unless pos = head_content_start(bytes)
          i = pos
          loop do
            break unless lt = bytes_index(bytes, '<'.ord.to_u8, i)
            if starts_with?(bytes, lt, "<!--")
              i = comment_end(bytes, lt)
              next
            end
            name_end = lt + 1
            while name_end < bytes.size && !tag_name_end?(bytes[name_end])
              name_end += 1
            end
            attrs, tag_end = parse_attributes(bytes, name_end)
            if name_end - lt == 5 && name_at?(bytes, lt + 1, "meta")
              return tag_end if charset_meta?(bytes, attrs)
              i = tag_end
            elsif name_end - lt == 6 && name_at?(bytes, lt + 1, "title")
              close = find_end_tag(bytes, "title", tag_end) || break
              i = (bytes_index(bytes, '>'.ord.to_u8, close) || break) + 1
            else
              break
            end
          end
          pos
        end

        # The offset just past the `<head>` start tag, skipping comments.
        private def self.head_content_start(bytes : Bytes) : Int32?
          i = 0
          loop do
            return unless lt = bytes_index(bytes, '<'.ord.to_u8, i)
            if starts_with?(bytes, lt, "<!--")
              i = comment_end(bytes, lt)
              next
            end
            if name_at?(bytes, lt + 1, "head") && (lt + 5 == bytes.size || tag_name_end?(bytes[lt + 5]))
              return parse_attributes(bytes, lt + 5)[1]
            end
            i = lt + 1
          end
        end

        private def self.charset_meta?(bytes : Bytes, attrs : Array(Attr)) : Bool
          attrs.any? do |attr|
            attr_named?(bytes, attr, "charset") ||
              (attr_named?(bytes, attr, "http-equiv") && attr_value(bytes, attr).try(&.strip.compare("content-type", case_insensitive: true)) == 0)
          end
        end

        # The URL path a page file is served at (`blog/x/index.html` →
        # `/blog/x/`), before `base_path`.
        def self.url_path(relative : String) : String
          relative = relative.tr("\\", "/")
          return "/" if relative == "index.html"
          return "/#{relative.rchop("index.html")}" if relative.ends_with?("/index.html")
          "/#{relative}"
        end

        # The headers file: the user's own file verbatim, then one block per
        # page. A user block that already sets `header` for a path wins.
        def self.headers_file(rules : Array({String, String}), header : String, user : String?) : String
          taken = user ? paths_setting(user, header) : Set(String).new
          String.build do |io|
            if user && !user.empty?
              io << user
              io << '\n' unless user.ends_with?('\n')
              io << '\n'
            end
            io << "# " << header << " generated by Hwaro ([csp])\n"
            rules.each do |path, policy|
              next if taken.includes?(path)
              io << path << "\n  " << header << ": " << policy << '\n'
            end
          end
        end

        # Paths whose block in a `_headers` file sets `header`.
        private def self.paths_setting(text : String, header : String) : Set(String)
          paths = Set(String).new
          current = nil
          text.each_line do |line|
            stripped = line.strip
            next if stripped.empty? || stripped.starts_with?('#')
            if line[0].whitespace?
              name = stripped.partition(':')[0].strip
              paths << current if current && name.compare(header, case_insensitive: true) == 0
            else
              current = stripped
            end
          end
          paths
        end

        # --- the build pass -------------------------------------------------

        # Hash every HTML page under `output_dir` (except the `excluded`
        # absolute paths: verbatim copies of user files) and emit the
        # policies. Returns what each page got, for the post-hook check.
        def self.apply(config : Models::Config, output_dir : String, excluded : Set(String), parallel : Bool = true) : Result
          csp = config.csp
          root = File.expand_path(output_dir)
          # Pages are independent: read, hash and (meta mode) rewrite them on
          # worker fibers, then collect in file order so output and warnings
          # stay deterministic.
          # Wrapped in a tuple: `map` drops nil results. An exception is
          # carried out and raised below rather than silently skipping a page.
          outcomes = Build::ParallelHelper.map(html_files(root), parallel) do |path|
            {apply_to_page(csp, root, path, excluded)}
          rescue ex
            ex
          end
          pages = outcomes.compact_map do |outcome|
            raise outcome if outcome.is_a?(Exception)
            outcome[0]
          end
          write_headers_file(config, root, pages) unless csp.meta?
          if csp.meta?
            dropped = csp.directives.keys.select { |name| META_IGNORED.includes?(name) && !csp.directives[name].empty? }
            unless dropped.empty?
              Logger.warn "[csp] mode = \"meta\" drops #{dropped.join(", ")}: browsers ignore #{dropped.size == 1 ? "it" : "them"} in a <meta> policy. Use mode = \"headers\" to send #{dropped.size == 1 ? "it" : "them"}."
            end
          end
          handler_pages = pages.select(&.handlers).map(&.relative)
          unless handler_pages.empty?
            Logger.warn "[csp] inline event handlers (onclick=…) are blocked by the policy on #{page_list(handler_pages)}. Move them into a script with addEventListener."
          end
          headless = pages.select(&.headless).map(&.relative)
          unless headless.empty?
            Logger.warn "[csp] no <head> to put the policy <meta> in, so these pages get no policy: #{page_list(headless)}."
          end
          Result.new(root, pages.to_h { |page| {page.path, page.policy} })
        end

        # Hash one page and, in meta mode, write its policy into it. Nil for
        # a file the pass leaves alone.
        private def self.apply_to_page(csp : Models::CspConfig, root : String, path : String, excluded : Set(String)) : PageResult?
          return if excluded.includes?(path)
          html = File.read(path)
          relative = Path[path].relative_to(root).to_posix.to_s
          return if static_copy?(relative, html) || amp?(html)
          # A `--cache` hit carries the meta a previous pass injected; hash
          # (and look for markers in) the page without it.
          clean = csp.meta? ? strip_meta(html) : html
          scan = scan(clean)
          policy = policy(csp, clean, scan)
          headless = false
          if csp.meta?
            if meta_position(html)
              updated = inject_meta(html, policy)
              Utils::FileSafe.atomic_write(path, updated) unless updated == html
            else
              headless = true
            end
          end
          PageResult.new(path, relative, policy, scan.handlers, headless)
        end

        # Headers mode: the user's file plus one rule per page, with the
        # warnings about what hosts will make of it.
        private def self.write_headers_file(config : Models::Config, root : String, pages : Array(PageResult)) : Nil
          csp = config.csp
          header = csp.report_only ? "Content-Security-Policy-Report-Only" : "Content-Security-Policy"
          user_label = File.join("static", csp.headers_file)
          user = File.file?(user_label) ? File.read(user_label) : nil
          rules = [] of {String, String}
          patterned = [] of String
          long = [] of String
          pages.each do |page|
            # `:` and `*` make a path line a placeholder or a splat, and a
            # control character breaks the file: such a rule would apply its
            # policy to other pages too.
            if page.relative.each_char.any? { |c| c.in?(':', '*') || c.control? }
              patterned << page.relative
              next
            end
            long << page.relative if header.bytesize + 2 + page.policy.bytesize > CLOUDFLARE_HEADER_LIMIT
            rules << {config.with_base_path(Utils::TextUtils.encode_url_path(url_path(page.relative))), page.policy}
          end
          rules.sort_by!(&.[0])
          headers_path = File.join(root, csp.headers_file)
          Utils::FileSafe.mkdir_p(File.dirname(headers_path))
          Utils::FileSafe.atomic_write(headers_path, headers_file(rules, header, user))

          unless patterned.empty?
            Logger.warn "[csp] no #{csp.headers_file} rule for #{page_list(patterned)}: `:`, `*` and control characters in a path make hosts read it as a pattern. Rename the page or use mode = \"meta\"."
          end
          unless long.empty?
            Logger.warn "[csp] #{header} is longer than #{CLOUDFLARE_HEADER_LIMIT} characters on #{page_list(long)}; Cloudflare Pages drops longer headers. Move inline code into files or use mode = \"meta\" there."
          end
          if rules.size > CLOUDFLARE_RULE_LIMIT
            Logger.warn "[csp] #{csp.headers_file} has #{rules.size} page rules; Cloudflare Pages reads at most #{CLOUDFLARE_RULE_LIMIT}. Netlify has no limit; elsewhere use mode = \"meta\"."
          end
          return unless user
          taken = paths_setting(user, header)
          replaced = rules.map(&.[0]).select { |path| taken.includes?(path) }
          unless replaced.empty?
            Logger.info "[csp] #{user_label} sets #{header} for #{page_list(replaced)}, so Hwaro writes no rule for #{replaced.size == 1 ? "it" : "them"}."
          end
          wildcards = taken.select { |path| path.includes?('*') || path.includes?(':') }.sort!
          unless wildcards.empty?
            Logger.warn "[csp] #{user_label} sets #{header} for #{wildcards.join(", ")}, which hosts combine with Hwaro's per-page rules: those pages get two policies and their inline code is blocked. Remove it, or turn [csp] off and keep your own policy."
          end
        end

        # Pages (output-relative) whose inline bytes a `[build] hooks.post`
        # command changed after their policy was emitted.
        def self.changed_pages(config : Models::CspConfig, result : Result) : Array(String)
          result.policies.compact_map do |path, policy|
            html = File.read(path) rescue next
            html = strip_meta(html) if config.meta?
            Path[path].relative_to(result.root).to_posix.to_s unless policy(config, html) == policy
          end.sort!
        end

        private def self.page_list(pages : Array(String)) : String
          more = pages.size > 5 ? " and #{pages.size - 5} more" : ""
          "#{pages.first(5).join(", ")}#{more}"
        end

        # A verbatim copy of `static/<relative>` is the user's file, not a
        # page Hwaro rendered: left alone, like `[content.files]` copies.
        private def self.static_copy?(relative : String, html : String) : Bool
          source = File.join("static", relative)
          File.file?(source) && File.read(source) == html
        end

        # AMP pages are left alone: the AMP runtime injects its styles at
        # run time, which a hash-based policy blocks.
        private def self.amp?(html : String) : Bool
          bytes = html.to_slice
          i = 0
          while lt = bytes_index(bytes, '<'.ord.to_u8, i)
            if lt + 5 < bytes.size && name_at?(bytes, lt + 1, "html") && tag_name_end?(bytes[lt + 5])
              return parse_attributes(bytes, lt + 5)[0].any? do |attr|
                attr_named?(bytes, attr, "amp") || bytes[attr[0], attr[1]] == "⚡".to_slice
              end
            end
            i = lt + 1
          end
          false
        end

        private def self.html_files(root : String) : Array(String)
          files = [] of String
          walk(root, files)
          files.sort!
        end

        private def self.walk(dir : String, files : Array(String)) : Nil
          Dir.each_child(dir) do |entry|
            path = File.join(dir, entry)
            info = File.info?(path, follow_symlinks: false) || next
            if info.directory?
              walk(path, files)
            elsif info.file? && entry.ends_with?(".html")
              files << path
            end
          end
        rescue File::Error
        end
      end
    end
  end
end
