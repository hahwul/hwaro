# The text half of the built-in `include_code` / `include_md` shortcodes and
# of `![[note]]` transclusion: path guard, region / line selection, dedent,
# the fenced block and the heading section. The builder (`expand_includes`
# in phases/parse_content.cr) finds the calls and splices what these return
# into the page's Markdown BEFORE shortcodes run, so the included text takes
# the normal pipeline — highlighting, fence options, the copy button,
# render hooks, shortcodes, the TOC and heading ids — as if it were written
# at that spot.

require "html"
require "./fence_tracker"
require "./syntax_highlighter"
require "../../utils/frontmatter_scanner"
require "../../utils/errors"
require "../../utils/path_utils"
require "../../utils/text_utils"

module Hwaro
  module Content
    module Processors
      module Includes
        extend self

        # A bad call: the builder prefixes the page and the call, then raises
        # it as a template error.
        class Error < Exception
        end

        # The build error an include or transclusion failure surfaces as
        # (HWARO_E_TEMPLATE, exit 4). Its own type, so the summary passes can
        # leave the report to the body render instead of repeating it.
        class IncludeError < Hwaro::HwaroError
          def initialize(message : String)
            super(Hwaro::Errors::HWARO_E_TEMPLATE, message)
          end
        end

        # The file does not exist (yet). Unlike a refusal, the caller still
        # tracks the path, so creating the file re-renders the page.
        class MissingFile < Error
        end

        MAX_DEPTH = 8

        # `#region name` / `#endregion name` after any comment leader (`//`,
        # `#`, `--`, `<!--`, `/*`, `;`). A name is a word run that may hold
        # `.` and inner `-`, so `<!-- #region brew-->` still reads `brew`.
        CODE_REGION_RE = /\A[ \t]*(?:\/\/+|\/\*+|<!--|--|;+|#)?[ \t]*#(end)?region\b[ \t]*([\w.]+(?:-[\w.]+)*)?/
        # Markdown only takes the HTML-comment form: any other leader is text
        # (or code inside a fence) in a Markdown file.
        MD_REGION_RE = /\A[ \t]*<!--[ \t]*#(end)?region\b[ \t]*([\w.]+(?:-[\w.]+)*)?[ \t]*-->[ \t]*\r?\n?\z/
        LINES_RE     = /\A[ \t]*(\d+)(?:[ \t]*-[ \t]*(\d+))?[ \t]*\z/
        SETEXT_RE    = /\A {0,3}(=+|-+)[ \t]*\r?\n?\z/
        THEMATIC_RE  = /\A {0,3}(?:(?:\*[ \t]*){3,}|(?:_[ \t]*){3,}|(?:-[ \t]*){3,})\r?\n?\z/
        ATX_RE       = /\A {0,3}(\#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*\r?\n?\z/

        # The fence-option keys `include_code` passes through, in the order
        # they are written (`title` is the alias `FenceOptions` reads as `name`).
        FENCE_OPTION_KEYS = %w[title name hl_lines hide_lines linenos linenostart copy]

        # `path` as a project-relative path, or an Error for an absolute path
        # or one that climbs out (`..`). Lexical only: `read` re-checks the
        # real path, so a symlink cannot reach outside either. The decoded
        # segments only decide the refusal (`%2e%2e` climbs too); the path
        # read is the literal one, so `a%20b.txt` names that file.
        def relative_path(path : String) : String
          raise Error.new("path is empty") if path.strip.empty?
          raise Error.new("absolute paths are refused: #{path}") if Utils::PathUtils.absolute?(path) || path.includes?('\0')
          literal = path.split('/').reject { |segment| segment.empty? || segment == "." }
          _, refused = Utils::PathUtils.split_safe_segments(literal.join('/'))
          raise Error.new("path escapes the project root: #{path}") if refused || literal.empty?
          literal.join('/')
        end

        # The bytes of the project file `relative` (see `clean`). Refused when its path —
        # as written, and with symlinks resolved — leaves the project root or
        # lands in `.hwaro/` or the build output: reading the output would be
        # a rebuild loop.
        def read(relative : String, output_dir : String?) : String
          root = File.realpath(Dir.current)
          refuse_output(File.join(root, relative), relative, root, output_dir)
          real = begin
            File.realpath(File.join(root, relative))
          rescue File::Error
            raise MissingFile.new("file not found: #{relative}")
          end
          unless Utils::PathUtils.within?(real, root)
            raise Error.new("#{relative} resolves outside the project root and is refused")
          end
          refuse_output(real, relative, root, output_dir)
          raise Error.new("not a file: #{relative}") unless File.info(real).file?
          File.read(real)
        rescue ex : File::Error | IO::Error
          raise Error.new("cannot read #{relative}: #{ex.message}")
        end

        private def refuse_output(path : String, relative : String, root : String, output_dir : String?) : Nil
          if Utils::PathUtils.within?(path, File.join(root, ".hwaro")) ||
             (output_dir && Utils::PathUtils.within?(path, File.expand_path(output_dir, root)))
            raise Error.new("#{relative} is inside the build output and is refused")
          end
        end

        # Invalid UTF-8 scrubbed, a BOM dropped, and NUL replaced the way
        # CommonMark does: the shortcode and Markdown passes use NUL-delimited
        # tokens, and a NUL in source would forge one.
        def clean(text : String) : String
          text = text.scrub.lchop('\u{FEFF}')
          text.includes?('\0') ? text.gsub('\0', '\u{FFFD}') : text
        end

        def strip_front_matter(text : String) : String
          Utils::FrontmatterScanner.strip_frontmatter(text)
        end

        # The lines between `#region name` and its `#endregion`, with every
        # marker inside dropped. A bare `#endregion` closes the innermost open
        # region.
        def region(text : String, name : String, markdown : Bool) : String
          re = markdown ? MD_REGION_RE : CODE_REGION_RE
          inside = false
          open = [] of String
          String.build do |io|
            text.each_line(chomp: false) do |line|
              if m = re.match(line)
                marker = m[2]? || ""
                if !inside
                  inside = true if m[1]?.nil? && marker == name
                elsif m[1]?.nil?
                  open << marker
                elsif marker == name || (marker.empty? && open.empty?)
                  return io.to_s
                else
                  open.pop?
                end
                next
              end
              io << line if inside
            end
            raise Error.new(inside ? "region '#{name}' is never closed" : "region '#{name}' not found")
          end
        end

        # Lines `spec` ("a-b" or "a", 1-based, inclusive) of `text`.
        def lines(text : String, spec : String) : String
          m = LINES_RE.match(spec)
          raise Error.new("lines=\"#{spec}\" is not a range like \"2-8\"") unless m
          all = text.lines(chomp: false)
          first = m[1].to_i? || 0
          last = m[2]?.try(&.to_i?) || (m[2]? ? 0 : first)
          if first < 1 || last < first || last > all.size
            raise Error.new("lines=\"#{spec}\" is out of range (#{all.size} #{all.size == 1 ? "line" : "lines"})")
          end
          all[(first - 1)..(last - 1)].join
        end

        # `text` without the leading whitespace every non-blank line shares.
        def dedent(text : String) : String
          lines = text.lines(chomp: false)
          prefix : String? = nil
          lines.each do |line|
            next if line.blank?
            lead = line[0, line.size - line.lstrip(" \t").size]
            prefix = prefix.nil? ? lead : common_prefix(prefix, lead)
            break if prefix.empty?
          end
          return text if prefix.nil? || prefix.empty?
          lines.join { |line| line.blank? ? line.lstrip(" \t") : line[prefix.size..] }
        end

        private def common_prefix(a : String, b : String) : String
          n = 0
          while n < a.size && n < b.size && a[n] == b[n]
            n += 1
          end
          a[0, n]
        end

        # The highlighter's lexer for `path`: the whole-name entry in
        # Tartrazine's filename table (`Makefile`, `CMakeLists.txt`), else its
        # `*.ext` entry, else the first glob matching the base name
        # (`Dockerfile.dev`). The table's names are lowercase, so the base
        # name is matched lowercased. "" when nothing matches.
        def language_for(path : String) : String
          base = File.basename(path)
          low = base.downcase
          if names = Tartrazine::LEXERS_BY_FILENAME[low]?
            return names.first
          end
          ext = File.extname(base)
          unless ext.empty?
            if names = Tartrazine::LEXERS_BY_FILENAME["*#{ext}"]? || Tartrazine::LEXERS_BY_FILENAME["*#{ext.downcase}"]?
              return names.first
            end
          end
          Tartrazine::LEXERS_BY_FILENAME.each do |glob, lexers|
            return lexers.first if File.match?(glob, low)
          end
          ""
        end

        # Tartrazine lexer names highlight.js knows under another name. Client
        # mode puts the lexer in the fence's class; server mode needs it as is.
        HLJS_NAMES = {
          "react" => "jsx", "mysql" => "sql", "cassandra_cql" => "sql", "protocol_buffer" => "protobuf",
          "txtpb" => "protobuf", "c#" => "csharp", "c++" => "cpp", "batchfile" => "dos",
          "bash_session" => "shell", "viml" => "vim", "vb_net" => "vbnet", "common_lisp" => "lisp",
          "emacslisp" => "lisp", "systemverilog" => "verilog", "objectpascal" => "delphi",
          "nginx_configuration_file" => "nginx", "apacheconf" => "apache", "standard_ml" => "sml",
          "docker" => "dockerfile",
        }

        # The highlight.js language for a Tartrazine lexer name.
        def hljs_language(lexer : String) : String
          HLJS_NAMES[lexer]? || lexer
        end

        # A fenced code block of `code`, longer than any backtick run inside
        # it. `options` are fence options (`title`, `hl_lines`, …); a value
        # loses the characters the fence-option grammar cannot hold.
        def fenced(code : String, lang : String, options : Hash(String, String)) : String
          code += "\n" unless code.empty? || code.ends_with?('\n')
          longest = 0
          code.scan(/`+/) { |m| longest = m[0].size if m[0].size > longest }
          fence = "`" * Math.max(3, longest + 1)
          info = lang.gsub(/[\s`{}]/, "")
          pairs = FENCE_OPTION_KEYS.compact_map do |key|
            value = options[key]?.try(&.gsub(/["{}`\r\n]/, ""))
            %(#{key}="#{value}") if value && !value.empty?
          end
          info += "#{info.empty? ? "" : " "}{#{pairs.join(", ")}}" unless pairs.empty?
          "#{fence}#{info}\n#{code}#{fence}\n"
        end

        # The section of `markdown` under the heading (ATX or setext) whose
        # slug matches `heading`'s, through the line before the next heading
        # of the same or a higher level. A heading is matched by the text it
        # renders (link and image syntax, tags and entities reduced to what
        # the reader sees), the id the build gives it. Headings inside code
        # fences do not count.
        def heading_section(markdown : String, heading : String) : String?
          want = Utils::TextUtils.slugify(heading)
          lines = markdown.lines(chomp: false)
          heads = section_headings(lines)
          found = heads.index { |_, _, text| Utils::TextUtils.slugify(text) == want }
          return unless found
          first, level, _ = heads[found]
          stop = heads[(found + 1)..].find { |_, other, _| other <= level }.try(&.[0]) || lines.size
          lines[first...stop].join
        end

        # `{first line, level, visible text}` of every heading outside code.
        private def section_headings(lines : Array(String)) : Array({Int32, Int32, String})
          tracker = FenceTracker.new
          heads = [] of {Int32, Int32, String}
          para = nil.as(Int32?) # first line of the paragraph being read
          skip = false          # inside a list item, quote or HTML block: no setext heading
          lines.each_with_index do |line, i|
            if tracker.fence_line?(line)
              para, skip = nil, false
            elsif m = ATX_RE.match(line)
              text = (m[2]? || "").sub(/[ \t]*\{[^{}]*\}\z/, "")
              heads << {i, m[1].size, visible_text(text)}
              para, skip = nil, false
            elsif line.blank?
              para, skip = nil, false
            elsif (start = para) && (u = SETEXT_RE.match(line))
              text = lines[start...i].join(' ', &.strip)
              heads << {start, u[1].starts_with?('=') ? 1 : 2, visible_text(text)}
              para = nil
            elsif tracker.html_block_line? || tracker.list_item_line? || line.lstrip(' ').starts_with?('>')
              para, skip = nil, true
            elsif THEMATIC_RE.matches?(line)
              para = nil
            elsif !skip
              para ||= i
            end
          end
          heads
        end

        # A heading's source as the reader sees it: images and links reduced
        # to their text, tags dropped, entities decoded.
        private def visible_text(source : String) : String
          text = source.gsub(/!\[([^\]]*)\]\([^)]*\)/, "\\1")
            .gsub(/\[([^\]]+)\](?:\([^)]*\)|\[[^\]]*\])/, "\\1")
            .gsub(/<(?:([A-Za-z][A-Za-z0-9+.-]*:[^\s<>]*)|\/?[A-Za-z][^<>]*)>/) { $1? || "" }
          HTML.unescape(text)
        end
      end
    end
  end
end
