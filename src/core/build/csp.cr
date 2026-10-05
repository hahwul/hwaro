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

        # The outcome of one build's pass: page file → the policy it got.
        record Result, policies : Hash(String, String), handler_pages : Array(String)

        # Sources a feature Hwaro itself emits needs, keyed by a URL prefix
        # the feature leaves in the page. A page gets a row's sources only
        # when its final HTML contains the marker, so a CDN that `[privacy]`
        # localized, or a shortcode the page does not use, adds nothing.
        FEATURE_SOURCES = [
          {marker: "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/", sources: {"script-src" => "https://cdnjs.cloudflare.com", "style-src" => "https://cdnjs.cloudflare.com"}},
          {marker: "https://cdn.jsdelivr.net/npm/katex@", sources: {"script-src" => "https://cdn.jsdelivr.net", "style-src" => "https://cdn.jsdelivr.net", "font-src" => "https://cdn.jsdelivr.net"}},
          {marker: "https://cdn.jsdelivr.net/npm/mathjax@", sources: {"script-src" => "https://cdn.jsdelivr.net", "font-src" => "https://cdn.jsdelivr.net"}},
          {marker: "https://cdn.jsdelivr.net/npm/mermaid@", sources: {"script-src" => "https://cdn.jsdelivr.net"}},
          {marker: "https://www.youtube.com/embed/", sources: {"frame-src" => "https://www.youtube.com"}},
          {marker: "https://player.vimeo.com/video/", sources: {"frame-src" => "https://player.vimeo.com"}},
          {marker: "https://gist.github.com/", sources: {"script-src" => "https://gist.github.com", "style-src" => "https://github.githubassets.com"}},
          {marker: "https://platform.twitter.com/widgets.js", sources: {"script-src" => "https://platform.twitter.com", "frame-src" => "https://platform.twitter.com"}},
          {marker: "https://codepen.io/", sources: {"frame-src" => "https://codepen.io"}},
        ]

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
            next unless Utils::ByteScan.includes?(html, row[:marker])
            row[:sources].each { |directive, source| add_source(dirs, directive, source) }
          end
          scan.scripts.each do |h|
            add_source(dirs, "script-src", h)
            add_source(dirs, "script-src-elem", h) if dirs.has_key?("script-src-elem")
          end
          scan.styles.each do |h|
            add_source(dirs, "style-src", h)
            add_source(dirs, "style-src-elem", h) if dirs.has_key?("style-src-elem")
          end
          unless scan.style_attrs.empty?
            dirs["style-src-attr"] = "" unless dirs.has_key?("style-src-attr")
            add_source(dirs, "style-src-attr", "'unsafe-hashes'")
            scan.style_attrs.each { |h| add_source(dirs, "style-src-attr", h) }
          end
          META_IGNORED.each { |name| dirs.delete(name) } if meta
          dirs.join("; ") { |name, value| value.empty? ? name : "#{name} #{value}" }
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
        def self.apply(config : Models::Config, output_dir : String, excluded : Set(String)) : Result
          csp = config.csp
          root = File.expand_path(output_dir)
          headers_path = File.join(root, csp.headers_file)
          policies = {} of String => String
          rules = [] of {String, String}
          handler_pages = [] of String
          headless = [] of String
          html_files(root).each do |path|
            next if excluded.includes?(path)
            html = File.read(path)
            relative = Path[path].relative_to(root).to_posix.to_s
            next if static_copy?(relative, html) || amp?(html)
            scan = scan(html)
            handler_pages << relative if scan.handlers
            policy = policy(csp, html, scan)
            policies[path] = policy
            if !csp.meta?
              rules << {config.with_base_path(Utils::TextUtils.encode_url_path(url_path(relative))), policy}
            elsif meta_position(html)
              updated = inject_meta(html, policy)
              Utils::FileSafe.atomic_write(path, updated) unless updated == html
            else
              headless << relative
            end
          end
          unless csp.meta?
            rules.sort_by!(&.[0])
            user_path = File.join("static", csp.headers_file)
            user = File.file?(user_path) ? File.read(user_path) : nil
            header = csp.report_only ? "Content-Security-Policy-Report-Only" : "Content-Security-Policy"
            Utils::FileSafe.mkdir_p(File.dirname(headers_path))
            Utils::FileSafe.atomic_write(headers_path, headers_file(rules, header, user))
            if rules.size > CLOUDFLARE_RULE_LIMIT
              Logger.warn "[csp] #{csp.headers_file} has #{rules.size} page rules; Cloudflare Pages reads at most #{CLOUDFLARE_RULE_LIMIT}. Netlify has no limit; elsewhere use mode = \"meta\"."
            end
          end
          if csp.meta?
            dropped = csp.directives.keys.select { |name| META_IGNORED.includes?(name) && !csp.directives[name].empty? }
            unless dropped.empty?
              Logger.warn "[csp] mode = \"meta\" drops #{dropped.join(", ")}: browsers ignore #{dropped.size == 1 ? "it" : "them"} in a <meta> policy. Use mode = \"headers\" to send #{dropped.size == 1 ? "it" : "them"}."
            end
          end
          unless handler_pages.empty?
            Logger.warn "[csp] inline event handlers (onclick=…) are blocked by the policy on #{page_list(handler_pages)}. Move them into a script with addEventListener."
          end
          unless headless.empty?
            Logger.warn "[csp] no <head> to put the policy <meta> in, so these pages get no policy: #{page_list(headless)}."
          end
          Result.new(policies, handler_pages)
        end

        # Pages whose inline bytes a `[build] hooks.post` command changed
        # after their policy was emitted.
        def self.changed_pages(config : Models::CspConfig, policies : Hash(String, String)) : Array(String)
          policies.compact_map do |path, policy|
            html = File.read(path) rescue next
            path unless policy(config, html) == policy
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
