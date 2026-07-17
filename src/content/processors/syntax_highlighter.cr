# Syntax Highlighter for code blocks
#
# This module provides syntax highlighting support by rendering
# code blocks with proper classes for client-side highlighting
# using Highlight.js or similar libraries.
#
# With `[highlight] mode = "server"`, code is highlighted at build time
# instead: Tartrazine lexers tokenize the code and tokens are emitted as
# spans with Highlight.js-compatible CSS classes, so existing hljs themes
# keep working and no JavaScript ships to the browser.
#
# Usage:
#   - Enable in config.toml with [highlight] section
#   - Include CSS/JS in templates using highlight_css and highlight_js helpers
#   - Code blocks will be rendered with language-* classes

require "markd"
require "tartrazine"
require "../../ext/tartrazine_mt_fix"
require "digest/md5"
require "./table_parser"
require "./markdown_extensions"
require "./heading_ids"
require "./render_hooks"
require "set"

module Hwaro
  module Content
    module Processors
      # Build-time highlighter: Tartrazine lexers + hljs-compatible classes.
      module ServerHighlighter
        extend self

        # Pygments/Chroma token-type prefixes mapped to Highlight.js classes,
        # checked in order — first matching prefix wins, so more specific
        # prefixes must precede their generic parent (KeywordType before Keyword).
        TOKEN_CLASS_PREFIXES = [
          {"CommentPreproc", "hljs-meta"},
          {"Comment", "hljs-comment"},
          {"KeywordConstant", "hljs-literal"},
          {"KeywordType", "hljs-type"},
          {"Keyword", "hljs-keyword"},
          {"NameKeyword", "hljs-keyword"},
          {"NameAttribute", "hljs-attr"},
          {"NameBuiltin", "hljs-built_in"},
          {"NameClass", "hljs-title class_"},
          {"NameConstant", "hljs-variable constant_"},
          {"NameDecorator", "hljs-meta"},
          {"NameEntity", "hljs-symbol"},
          {"NameException", "hljs-title class_"},
          {"NameFunction", "hljs-title function_"},
          {"NameLabel", "hljs-symbol"},
          {"NameNamespace", "hljs-title class_"},
          {"NameProperty", "hljs-property"},
          {"NameTag", "hljs-name"},
          {"NameVariable", "hljs-variable"},
          {"NameOperator", "hljs-operator"},
          {"LiteralDate", "hljs-string"},
          {"LiteralNumber", "hljs-number"},
          {"LiteralStringEscape", "hljs-string"},
          {"LiteralStringInterpol", "hljs-subst"},
          {"LiteralStringRegex", "hljs-regexp"},
          {"LiteralStringSymbol", "hljs-symbol"},
          {"LiteralStringDoc", "hljs-doctag"},
          {"LiteralString", "hljs-string"},
          {"Literal", "hljs-literal"},
          {"OperatorWord", "hljs-keyword"},
          {"Operator", "hljs-operator"},
          {"Punctuation", "hljs-punctuation"},
          {"GenericDeleted", "hljs-deletion"},
          {"GenericInserted", "hljs-addition"},
          {"GenericHeading", "hljs-section"},
          {"GenericSubheading", "hljs-section"},
          {"GenericEmph", "hljs-emphasis"},
          {"GenericStrong", "hljs-strong"},
          {"GenericPrompt", "hljs-meta prompt_"},
        ]

        # Precomputed token-type → hljs class for every known token type.
        # Built once at program start from Tartrazine's own type list, so
        # lookups during parallel rendering are read-only and fiber-safe.
        TOKEN_CLASSES = begin
          map = {} of String => String?
          Tartrazine::Abbreviations.each_key do |token_type|
            map[token_type] = resolve_class(token_type)
          end
          map
        end

        # Languages Tartrazine has no lexer for — remembered to avoid
        # re-raising on every code block of that language.
        @@unknown_languages = Set(String).new
        @@unknown_mutex = Mutex.new

        # Tokenization runs in parallel across -Dpreview_mt workers.
        # It used to be serialized behind a global mutex here: the shard's
        # compiled rules each held a single PCRE2 match_data buffer reused
        # by every match() call and shared across lexer instances via the
        # template cache, so two workers tokenizing the same language
        # corrupted each other's matches (raising intermittently, which the
        # rescue below degraded to nondeterministic plain output). That
        # shared state — and the template cache's unsynchronized fast path,
        # and `combined` actions mutating the shared states Hash — is fixed
        # at the source in ext/tartrazine_mt_fix.cr, so correctness no
        # longer needs a lock around Tartrazine work.
        #
        # Concurrency is still BOUNDED, not unlimited: tokenization is
        # allocation-dense (token values, per-rule arrays), and past ~4
        # simultaneous tokenizers the Boehm GC's global allocation lock
        # becomes a convoy that slows the WHOLE build (measured: a
        # 5k-page site with 10k unique code blocks at 8 workers built
        # ~25% slower fully unbounded than with this cap, while small and
        # mid-size sites kept their full parallel speedup). A buffered
        # channel acts as a counting semaphore; blocked fibers suspend —
        # the worker thread moves on to other pages meanwhile.
        TOKENIZE_SLOTS = 4
        @@tokenize_gate = Channel(Nil).new(TOKENIZE_SLOTS)

        # Highlighted-output memo keyed by (language, code digest). Output
        # is a pure function of the input pair, so identical code blocks —
        # repeated install snippets, shortcode bodies, serve-mode rebuilds —
        # skip tokenization entirely. `nil`
        # (tokenization failed, deterministic now) is cached too.
        #
        # Cache holds pre-wrap span HTML only; key (lang, md5(code)) stays
        # complete — never cache post-wrap output under this key. Fence
        # options (line numbers / hl_lines) are applied afterwards by
        # `LineWrapper`, a pure string transform over this cached result, so
        # the same highlighted body can be reused unwrapped or wrapped with
        # any combination of options without invalidating the entry.
        @@result_cache = {} of String => String?
        @@result_mutex = Mutex.new
        # Blocks larger than this are highlighted but not cached, keeping
        # memory bounded; the entry cap guards pathological unique-block
        # counts (clear-on-full is deterministic for output, only a speed
        # hit).
        MAX_CACHED_BLOCK_BYTES = 65_536
        MAX_CACHE_ENTRIES      =  2_048

        # Highlight `code` as `lang`, returning HTML-escaped markup with
        # hljs-class spans — or nil when no lexer exists for the language
        # (callers fall back to plain client-style output).
        def highlight(code : String, lang : String) : String?
          normalized = lang.downcase
          return if @@unknown_mutex.synchronize { @@unknown_languages.includes?(normalized) }

          cacheable = code.bytesize <= MAX_CACHED_BLOCK_BYTES
          cache_key = "#{normalized}\0#{Digest::MD5.hexdigest(code)}" if cacheable
          if cache_key
            @@result_mutex.synchronize do
              return @@result_cache[cache_key] if @@result_cache.has_key?(cache_key)
            end
          end

          lexer = begin
            Tartrazine.lexer(normalized)
          rescue
            @@unknown_mutex.synchronize { @@unknown_languages << normalized }
            Logger.debug "Server highlight: no lexer for '#{normalized}', falling back to plain output"
            return
          end

          @@tokenize_gate.send(nil)
          result = begin
            String.build do |io|
              lexer.tokenizer(code).each do |token|
                value = token[:value]
                # Most tokens (keywords, identifiers, whitespace) need no
                # escaping — skip HTML.escape's char-by-char rebuild for them.
                value = HTML.escape(value) if needs_html_escape?(value)
                if css_class = class_for(token[:type])
                  io << %(<span class=") << css_class << %(">) << value << "</span>"
                else
                  io << value
                end
              end
            end
          rescue ex
            # A lexer bug must never take down the build — degrade to plain.
            Logger.debug "Server highlight failed for '#{lang}': #{ex.message}"
            nil
          ensure
            @@tokenize_gate.receive
          end

          if cache_key
            @@result_mutex.synchronize do
              @@result_cache.clear if @@result_cache.size >= MAX_CACHE_ENTRIES
              @@result_cache[cache_key] = result
            end
          end
          result
        end

        # True when `value` contains any character HTML.escape substitutes
        # (`& < > " '` — see HTML::SUBSTITUTIONS) or any non-ASCII byte.
        # The five specials are ASCII, so the byte scan is exact for UTF-8.
        #
        # Bytes >= 0x80 are routed through HTML.escape too — NOT because
        # they need escaping, but because a token can be invalid UTF-8:
        # the tokenizer's Error fallback emits unmatched input one BYTE at
        # a time, so a multi-byte character no rule matched arrives as
        # lone lead/continuation bytes. The String-returning HTML.escape
        # iterates chars and replaces those with U+FFFD, exactly like the
        # pre-fast-path code always did; skipping it would leak invalid
        # UTF-8 into the output HTML. (Valid multi-byte text passes
        # through escape content-unchanged, so this only costs the clean
        # fast path for non-ASCII tokens — do not "optimize" this onto
        # the HTML.escape(value, io) overload, which copies raw bytes and
        # performs no U+FFFD replacement.)
        private def needs_html_escape?(value : String) : Bool
          value.each_byte do |byte|
            case byte
            when 0x26_u8, 0x3C_u8, 0x3E_u8, 0x22_u8, 0x27_u8 # & < > " '
              return true
            else
              return true if byte >= 0x80_u8
            end
          end
          false
        end

        private def class_for(token_type : String) : String?
          return TOKEN_CLASSES[token_type] if TOKEN_CLASSES.has_key?(token_type)
          resolve_class(token_type)
        end

        private def resolve_class(token_type : String) : String?
          TOKEN_CLASS_PREFIXES.each do |prefix, css_class|
            return css_class if token_type.starts_with?(prefix)
          end
          nil
        end
      end

      # Parses the Zola/Pandoc-ish `{linenos=true, hl_lines="2-4 7",
      # linenostart=5, hide_lines="1 9-12"}` fence-info suffix that can
      # follow a fenced code block's language token.
      #
      # Grammar: an info string is `LANG`, `LANG {OPTS}`, `LANG{OPTS}`, or
      # `{OPTS}`. It only ACTIVATES the options path when the stripped info
      # ends with `}`, contains a `{`, the substring from the first `{` to
      # the end is exactly `{...}` (no nested/unbalanced braces), and
      # tokenizing the inside yields at least one recognized, validly-valued
      # key. Anything else (no braces, unterminated `{`, unparsable tokens,
      # or only unknown/invalid keys) falls back to the legacy behavior:
      # the whole info string is treated as a plain language token, exactly
      # as it was before fence options existed.
      module FenceOptions
        extend self

        # A parsed `{...}` fence-options block.
        # `hl_lines` and `hide_lines` are stored as (start, end) ranges —
        # NEVER expanded into a Set of individual line numbers, so a
        # pathological `hl_lines="1-100000"` costs a handful of bytes, not
        # 100k Int32s.
        # `name` is the filename/title label (`{name="main.cr"}`, `title=`
        # accepted as an alias) rendered above the code block.
        record Options, linenos : Bool? = nil, linenostart : Int32 = 1, hl_lines : Array({Int32, Int32}) = [] of {Int32, Int32}, name : String? = nil, hide_lines : Array({Int32, Int32}) = [] of {Int32, Int32}, copy : Bool? = nil do
          def hl?(physical_line : Int32) : Bool
            hl_lines.any? { |(a, b)| physical_line >= a && physical_line <= b }
          end

          def hidden?(physical_line : Int32) : Bool
            hide_lines.any? { |(a, b)| physical_line >= a && physical_line <= b }
          end
        end

        # `key=value` / `key="quoted value"` pairs, comma/whitespace
        # separated. `\G` anchors each successive match to the end of the
        # previous one (via the `pos` argument to `match`), so any leftover
        # text that isn't whitespace/commas between valid pairs shows up as
        # unconsumed residue — the caller uses that to invalidate the whole
        # block rather than silently ignoring garbage.
        PAIR_RE        = /\G[\s,]*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("([^"]*)"|[^\s,}"]+)/
        BRACE_RE       = /\A\{([^{}]*)\}\z/
        BOOL_TRUE_RE   = /\Atrue\z/i
        BOOL_FALSE_RE  = /\Afalse\z/i
        LINENOSTART_RE = /\A\d+\z/
        HL_ITEM_RE     = /\A(\d+)(?:-(\d+))?\z/

        LINENOSTART_MAX = 1_000_000
        HL_LINE_MAX     =   100_000

        # Returns `{lang, opts}`. `lang` is the language token to use for
        # highlighting (the text before the first `{`, or the whole info
        # string when no options block is present/active — "as today").
        # `opts` is `nil` whenever the options block isn't present or
        # doesn't parse — callers then fall back to legacy behavior keyed
        # only on `lang`.
        def parse(info : String?) : {String?, Options?}
          return {nil, nil} unless info
          stripped = info.strip
          return {nil, nil} if stripped.empty?

          legacy_lang = stripped.split.first?
          return {legacy_lang, nil} unless stripped.ends_with?('}')

          brace_index = stripped.index('{')
          return {legacy_lang, nil} unless brace_index

          brace_part = stripped[brace_index..]
          match = BRACE_RE.match(brace_part)
          return {legacy_lang, nil} unless match

          inner = match[1]
          pairs, residue_start = tokenize_pairs(inner)
          residue = inner[residue_start..]
          return {legacy_lang, nil} unless residue.gsub(/[\s,]/, "").empty?

          linenos : Bool? = nil
          linenostart = 1
          hl_lines = [] of {Int32, Int32}
          hide_lines = [] of {Int32, Int32}
          name : String? = nil
          copy : Bool? = nil
          recognized = 0

          pairs.each do |key, value|
            case key.downcase
            when "name", "title"
              # Zola's `name` and Hugo-familiar `title` set the same label;
              # last one wins. Empty values are ignored (don't activate).
              if label = value.presence
                name = label
                recognized += 1
              end
            when "linenos"
              if BOOL_TRUE_RE.matches?(value)
                linenos = true
                recognized += 1
              elsif BOOL_FALSE_RE.matches?(value)
                linenos = false
                recognized += 1
              end
            when "copy"
              if BOOL_TRUE_RE.matches?(value)
                copy = true
                recognized += 1
              elsif BOOL_FALSE_RE.matches?(value)
                copy = false
                recognized += 1
              end
            when "linenostart"
              # `0` is rejected like a negative value (the regex already
              # blocks `-`), not silently clamped to line 1 — renumbering
              # from a line the author never asked for.
              if LINENOSTART_RE.matches?(value) && (n = value.to_i?) && n >= 1
                linenostart = n.clamp(1, LINENOSTART_MAX)
                recognized += 1
              end
            when "hl_lines"
              ranges = parse_hl_lines(value)
              unless ranges.empty?
                hl_lines = ranges
                recognized += 1
              end
            when "hide_lines"
              ranges = parse_hl_lines(value)
              unless ranges.empty?
                hide_lines = ranges
                recognized += 1
              end
            else
              # Unknown key — ignored, doesn't count toward activation.
            end
          end

          return {legacy_lang, nil} if recognized == 0

          lang = stripped[0, brace_index].strip.split.first?.try(&.presence)
          {lang, Options.new(linenos: linenos, linenostart: linenostart, hl_lines: hl_lines, name: name, hide_lines: hide_lines, copy: copy)}
        end

        # Scans `key=value` pairs from the start of `inner`. Returns the
        # pairs found and the CHAR offset where scanning stopped (either
        # end-of-string or the first position that doesn't extend a match) —
        # `Regex#match`'s `pos` argument and `MatchData#end` are both char
        # indices, so every offset here stays in char-index space (matters
        # only if a bare, unrecognized value contains multi-byte text).
        private def tokenize_pairs(inner : String) : {Array({String, String}), Int32}
          pairs = [] of {String, String}
          pos = 0
          len = inner.size
          while pos < len
            m = PAIR_RE.match(inner, pos)
            break unless m
            key = m[1]
            value = m[3]? || m[2]
            new_pos = m.end
            break unless new_pos > pos
            pairs << {key, value}
            pos = new_pos
          end
          {pairs, pos}
        end

        # `hl_lines` value → ranges. Individual malformed/out-of-order items
        # are dropped rather than invalidating the whole option (never
        # raises: matched purely via regex + `to_i?`).
        private def parse_hl_lines(value : String) : Array({Int32, Int32})
          ranges = [] of {Int32, Int32}
          value.split(/[,\s]+/).each do |item|
            next if item.empty?
            m = HL_ITEM_RE.match(item)
            next unless m
            start_n = m[1].to_i?
            next unless start_n
            end_n = m[2]?.try(&.to_i?) || start_n
            # Line numbers are 1-based: a literal `0` is invalid input and is
            # dropped like any other malformed item, not clamped up to line 1
            # (which silently highlighted a line the author never asked for).
            next if start_n < 1 || end_n < 1
            start_clamped = start_n.clamp(1, HL_LINE_MAX)
            end_clamped = end_n.clamp(1, HL_LINE_MAX)
            next if end_clamped < start_clamped
            ranges << {start_clamped, end_clamped}
          end
          ranges.uniq
        end
      end

      # Wraps already-highlighted (or plain-escaped) code body HTML with
      # per-line `<span class="line">` markup for line numbers / highlighted
      # lines — pure string post-processing, zero Tartrazine calls, applied
      # AFTER (and outside) `ServerHighlighter`'s gated tokenization, over
      # its already-cached result.
      module LineWrapper
        extend self

        SPAN_OPEN_PREFIX = "<span class=\""
        SPAN_CLOSE       = "</span>"

        # Splits already-highlighted HTML (a flat stream of
        # `<span class="...">ESCAPED</span>` and bare ESCAPED text — never
        # nested, and the escaped text never contains a raw `<`/`>`) into
        # one string per physical source line, re-opening any span whose
        # class carries across a newline (a token's value can itself
        # contain `\n`, e.g. a multi-line string literal).
        def split_lines(html : String) : Array(String)
          bytes = html.to_slice
          len = bytes.size
          lines = [] of String
          buf = String::Builder.new
          open_class : String? = nil
          pos = 0

          while pos < len
            byte = bytes[pos]
            if byte == 0x3C_u8 && match_at?(bytes, pos, SPAN_OPEN_PREFIX) # '<'
              close_quote = html.byte_index('"', pos + SPAN_OPEN_PREFIX.bytesize)
              if close_quote && close_quote + 1 < len && bytes[close_quote + 1] == 0x3E_u8 # '>'
                tag_end = close_quote + 2
                open_class = html.byte_slice(pos + SPAN_OPEN_PREFIX.bytesize, close_quote - (pos + SPAN_OPEN_PREFIX.bytesize))
                buf.write(bytes[pos, tag_end - pos])
                pos = tag_end
              else
                buf.write_byte(byte)
                pos += 1
              end
            elsif byte == 0x3C_u8 && match_at?(bytes, pos, SPAN_CLOSE)
              buf << SPAN_CLOSE
              open_class = nil
              pos += SPAN_CLOSE.bytesize
            elsif byte == 0x0A_u8 # '\n'
              buf << SPAN_CLOSE if open_class
              lines << buf.to_s
              buf = String::Builder.new
              pos += 1
              if open_class
                if match_at?(bytes, pos, SPAN_CLOSE)
                  pos += SPAN_CLOSE.bytesize
                  open_class = nil
                else
                  buf << SPAN_OPEN_PREFIX << open_class << "\">"
                end
              end
            else
              next_special = next_special_index(bytes, pos, len)
              buf.write(bytes[pos, next_special - pos])
              pos = next_special
            end
          end

          lines << buf.to_s
          lines.pop if html.ends_with?('\n') && lines.last?.try(&.empty?)
          lines
        end

        # Wraps each physical line of already-highlighted `body` in a
        # `<span class="line">` (` hl` appended for highlighted lines),
        # optionally prefixing a `<span class="ln">` gutter number.
        # `hl_lines`/`hide_lines` ranges are matched against the PHYSICAL
        # 1-based line number — never shifted by `linenostart`.
        #
        # Hidden lines are elided from the output but KEEP consuming their
        # physical line numbers, so the gutter shows gaps (unlike Zola,
        # which renumbers). This preserves the documented invariant that
        # `hl_lines` and `linenostart` always target physical lines.
        def wrap(body : String, linenos : Bool, start : Int32, opts : FenceOptions::Options) : String
          lines = split_lines(body)
          # Gutter width spans the full physical range, elided lines included.
          width = (start + lines.size - 1).to_s.size

          String.build do |io|
            lines.each_with_index do |line, i|
              next if opts.hidden?(i + 1)
              hl = opts.hl?(i + 1)
              io << %(<span class="line) << (hl ? " hl" : "") << %(">)
              if linenos
                io << %(<span class="ln" aria-hidden="true">) << (start + i).to_s.rjust(width) << ' ' << "</span>"
              end
              io << line << SPAN_CLOSE << '\n'
            end
          end
        end

        # True when `bytes[pos...]` starts with the literal ASCII `needle`.
        private def match_at?(bytes : Bytes, pos : Int32, needle : String) : Bool
          needle_bytes = needle.to_slice
          return false if pos + needle_bytes.size > bytes.size
          needle_bytes.each_with_index do |b, i|
            return false if bytes[pos + i] != b
          end
          true
        end

        # Index of the next `<` or `\n` at or after `pos`, or `len` if none.
        private def next_special_index(bytes : Bytes, pos : Int32, len : Int32) : Int32
          i = pos
          while i < len
            b = bytes[i]
            break if b == 0x3C_u8 || b == 0x0A_u8
            i += 1
          end
          i
        end
      end

      # Custom HTML renderer that adds syntax highlighting support
      # Extends Markd's HTMLRenderer to customize code block output
      class HighlightingRenderer < Markd::HTMLRenderer
        @highlight_enabled : Bool
        @server_mode : Bool

        def initialize(options : Markd::Options, @highlight_enabled : Bool = true, @server_mode : Bool = false)
          super(options)
        end

        # In server mode, emit pre-highlighted spans instead of plain escaped
        # text. Falls back to the default escaped output when the language has
        # no lexer (the `language-*` class is still present for styling).
        #
        # When fence options (line numbers / hl_lines) are present AND
        # active, the body is wrapped per-line instead — but ONLY in server
        # mode; client mode keeps this exact byte-for-byte legacy body no
        # matter what options were parsed (see `code_block`, which is what
        # adds the `data-*` attributes for the client-side case).
        def code_block_body(node : Markd::Node, lang : String?)
          highlight_lang, opts = resolve_options(node)

          if opts
            linenos = effective_linenos(opts)
            active = linenos || !opts.hl_lines.empty? || !opts.hide_lines.empty?

            if active && @highlight_enabled && @server_mode
              body = highlight_lang && (highlighted = ServerHighlighter.highlight(node.text, highlight_lang)) ? highlighted : escape(node.text)
              return literal(LineWrapper.wrap(body, linenos, opts.linenostart, opts))
            end
          end

          # Byte-identical fallback — options absent, inert, or client mode.
          if @highlight_enabled && @server_mode && lang
            if highlighted = ServerHighlighter.highlight(node.text, lang)
              return literal(highlighted)
            end
          end
          super
        end

        # Override code_block to add highlighting-specific attributes
        def code_block(node : Markd::Node, entering : Bool)
          languages = node.fence_language ? node.fence_language.split : nil
          code_tag_attrs = attrs(node)
          pre_tag_attrs = nil

          resolved_lang, opts = resolve_options(node)
          # When a fence-options block is present, the language for the class
          # must come from FenceOptions' stripped parse — not the raw split,
          # which for the no-space (`python{linenos=true}`) and no-language
          # (`{linenos=true}`) forms would leak the `{...}` into the class.
          lang = opts ? resolved_lang : code_block_language(languages)

          if @highlight_enabled && lang
            # Add classes for highlight.js
            code_tag_attrs ||= {} of String => String
            code_tag_attrs["class"] = "language-#{escape_lang(lang)} hljs"
          elsif lang
            code_tag_attrs ||= {} of String => String
            code_tag_attrs["class"] = "language-#{escape_lang(lang)}"
          end

          if opts
            linenos = effective_linenos(opts)
            active = linenos || !opts.hl_lines.empty? || !opts.hide_lines.empty?
            # Client-side attrs only: server mode bakes line numbers/hl
            # directly into the body, so the <pre> tag stays untouched.
            if active && !@server_mode
              pre_tag_attrs = {} of String => String
              pre_tag_attrs["data-linenos"] = "true" if linenos
              if linenos && opts.linenostart > 1
                pre_tag_attrs["data-linenostart"] = opts.linenostart.to_s
              end
              unless opts.hl_lines.empty?
                pre_tag_attrs["data-hl-lines"] = serialize_hl_lines(opts.hl_lines)
              end
              # Documented inert: Hwaro ships no client script acting on it.
              unless opts.hide_lines.empty?
                pre_tag_attrs["data-hide-lines"] = serialize_hl_lines(opts.hide_lines)
              end
            end
          end

          # Copy button marker — BOTH modes (the inline runtime from
          # `js_tag` targets `pre[data-copy]` regardless of who colored the
          # code). Never on mermaid fences: `postprocess_mermaid`'s regex
          # anchors on the bare `<pre><code class="language-mermaid...`
          # shape, so any attribute on <pre> would break the rewrite.
          if effective_copy(opts) && lang.try(&.downcase) != "mermaid"
            pre_tag_attrs ||= {} of String => String
            pre_tag_attrs["data-copy"] = "true"
          end

          # Filename/title label: a structural wrapper around the untouched
          # <pre> so it composes with server-mode line wrapping AND the
          # client-mode data-* attributes alike. Absent a name, the output
          # below is byte-identical to the pre-label code path.
          label = opts.try(&.name)

          newline
          literal(%(<div class="code-block"><div class="code-filename">#{escape_lang(label)}</div>)) if label
          tag("pre", pre_tag_attrs) do
            tag("code", code_tag_attrs) do
              code_block_body(node, lang)
            end
          end
          literal("</div>") if label
          newline
        end

        # Escape special HTML characters in language name
        private def escape_lang(text : String) : String
          HTML.escape(text)
        end

        # Resolves the language + fence-options for `node`, collapsing every
        # "nothing is active" case into `opts = nil` so both `code_block`
        # and `code_block_body` reduce to a single on/off branch:
        #
        # - highlighting disabled entirely
        # - `mermaid` (ALWAYS legacy — `postprocess_mermaid`'s regex matches
        #   the plain `<pre><code class="language-mermaid...">` shape, not a
        #   line-wrapped body)
        # - no recognized `{...}` block AND the global `line_numbers`
        #   default is off
        #
        # The returned language differs from `code_block`'s own
        # `code_block_language` computation only when an options block is
        # present (it strips the `{...}` suffix); the `<code>` tag's class
        # attribute always uses the unmodified original computation.
        private def resolve_options(node : Markd::Node) : {String?, FenceOptions::Options?}
          info = node.fence_language.presence
          lang, opts = FenceOptions.parse(info)

          return {lang, nil} unless @highlight_enabled
          return {lang, nil} if lang.try(&.downcase) == "mermaid"
          return {lang, opts} if opts

          if info && !info.includes?('{') && lang.presence && SyntaxHighlighter.default_line_numbers?
            return {lang, FenceOptions::Options.new(linenos: true)}
          end

          {lang, nil}
        end

        # Canonical `data-hl-lines` serialization: space-separated ranges in
        # parse order, single numbers collapsed (`"2-4 7"`, not `"2-4 7-7"`).
        private def serialize_hl_lines(ranges : Array({Int32, Int32})) : String
          ranges.map { |(a, b)| a == b ? a.to_s : "#{a}-#{b}" }.join(" ")
        end

        # A per-block `{linenos=...}` wins; otherwise fall back to the
        # module-wide `[highlight] line_numbers` default.
        private def effective_linenos(opts : FenceOptions::Options) : Bool
          explicit = opts.linenos
          explicit.nil? ? SyntaxHighlighter.default_line_numbers? : explicit
        end

        # Same override chain for the copy button (`{copy=...}` wins over
        # `[highlight] copy`). `opts` can be nil here: unlike the line
        # options, the global default applies to every fence, options
        # block or not.
        private def effective_copy(opts : FenceOptions::Options?) : Bool
          explicit = opts.try(&.copy)
          explicit.nil? ? SyntaxHighlighter.default_copy? : explicit
        end
      end

      # Renderer used only when at least one `templates/hooks/render-*`
      # template is configured (`RenderHooks.registry` is non-nil). Every
      # override starts with `return super unless @hooks.<hook>?`, so an
      # element the registry has no hook for renders exactly as
      # `HighlightingRenderer` would — this class adds no branches to the
      # stock class itself.
      #
      # Link/Image/Heading are containers (Markd's walker visits them
      # twice: entering, then leaving with their children already
      # rendered in between); the hook needs the children's rendered HTML
      # as a single string, so `push_capture`/`pop_capture` temporarily
      # swap `@output_io`/`@last_output` (the same buffer
      # `Markd::Renderer#literal`/`#output` write to) for a scratch
      # buffer, nesting correctly via `@capture_stack` for e.g. a link
      # inside a heading, or an image inside a link.
      class HookedRenderer < HighlightingRenderer
        @capture_stack = [] of {String::Builder, String}
        @used_heading_ids = Set(String).new
        @heading_id_counters = Hash(String, Int32).new(0)

        def initialize(options : Markd::Options, highlight_enabled : Bool, server_mode : Bool, @hooks : Content::Processors::RenderHooks::HookRenderContext)
          super(options, highlight_enabled, server_mode)
        end

        private def push_capture : Nil
          @capture_stack << {@output_io, @last_output}
          @output_io = String::Builder.new
          @last_output = "\n"
        end

        private def pop_capture : String
          inner = @output_io.to_s
          frame = @capture_stack.pop
          @output_io = frame[0]
          @last_output = frame[1]
          inner
        end

        def link(node : Markd::Node, entering : Bool)
          return super unless @hooks.link?
          return super if @disable_tag > 0

          if entering
            push_capture
          else
            text = pop_capture
            destination = node.data["destination"].as(String)
            title = node.data["title"].as(String)
            dest_out = (@options.safe? && potentially_unsafe(destination)) ? "" : escape(destination)
            literal(@hooks.render_link(destination: dest_out, title: escape(title), text: text))
          end
        end

        # Mirrors Markd::HTMLRenderer#image's `@disable_tag` protocol
        # exactly (see the module doc above): a link or another image
        # nested inside this image's alt text never gets its own tag, and
        # neither does a nested hook — it just contributes plain text to
        # this image's `alt`, same as stock.
        def image(node : Markd::Node, entering : Bool)
          return super unless @hooks.image?

          if entering
            push_capture if @disable_tag == 0
            @disable_tag += 1
          else
            @disable_tag -= 1
            if @disable_tag == 0
              alt = pop_capture
              destination = node.data["destination"].as(String)
              title = node.data["title"].as(String)
              dest_out = (@options.safe? && potentially_unsafe(destination)) ? "" : escape(destination)
              literal(@hooks.render_image(destination: dest_out, alt: alt, title: escape(title)))
            end
          end
        end

        def heading(node : Markd::Node, entering : Bool)
          return super unless @hooks.heading?
          return super if @disable_tag > 0

          if entering
            newline
            push_capture
          else
            inner = pop_capture

            # `## Heading {#custom-id}` (heading_ids extension) leaves a
            # `<!--HID:custom-id-->` marker in the rendered inline content —
            # extract it and strip it from the visible text, mirroring
            # `MarkdownExtensions.postprocess_heading_ids`.
            custom_id = nil
            if hid_match = inner.match(MarkdownExtensions::HID_MARKER_RE)
              custom_id = hid_match[1]
              inner = inner.sub(hid_match[0], "").rstrip
            elsif hattr_match = inner.match(MarkdownExtensions::HATTR_MARKER_RE)
              # `## Heading {#id .class}` (generalized attributes extension)
              # leaves a `<!--HATTR:...-->` marker instead. Pull just the
              # custom `#id` out of it so the hook's `id` variable — and any
              # `#{id}` anchors the template emits — match the id that
              # `postprocess_attributes` will ultimately set on the tag.
              # Leave the marker IN `inner`: postprocess still needs it to
              # merge the block's classes/other attributes onto the heading.
              if decoded = MarkdownAttributes.decode(hattr_match[1])
                if parsed = MarkdownAttributes.parse(decoded)
                  custom_id = parsed.id
                end
              end
            end

            title_text = strip_tags(inner)
            id = HeadingIds.assign(title_text, custom_id, @used_heading_ids, @heading_id_counters)
            level = node.data["level"].as(Int32)
            literal(@hooks.render_heading(level: level, text: inner, id: id))
            newline
          end
        end

        # CodeBlock is a leaf — the walker yields exactly one (entering:
        # true) event for it, matching `HighlightingRenderer#code_block`.
        def code_block(node : Markd::Node, entering : Bool)
          return super unless @hooks.codeblock?
          return super if @disable_tag > 0

          lang, opts = FenceOptions.parse(node.fence_language.presence)

          # `mermaid` fences stay on the existing pipeline (rendered as
          # stock `<pre><code class="language-mermaid...">`, later turned
          # into a `<div class="mermaid">` by `postprocess_mermaid`) when
          # mermaid is enabled — config decides who owns that fence, not
          # the hook template.
          return super if lang.try(&.downcase) == "mermaid" && @hooks.mermaid_bypass?

          info = node.fence_language.to_s.strip
          options_str = if idx = info.index('{')
                          info[idx..]
                        elsif sp = info.index(' ')
                          info[(sp + 1)..].strip
                        else
                          ""
                        end

          highlighted = (@highlight_enabled && @server_mode && lang) ? (ServerHighlighter.highlight(node.text, lang) || "") : ""

          copy_active = effective_copy(opts) && lang.try(&.downcase) != "mermaid"

          newline
          literal(@hooks.render_codeblock(
            lang: lang ? escape(lang) : "",
            options: escape(options_str),
            code: escape(node.text),
            highlighted: highlighted,
            name: opts.try(&.name).try { |n| escape(n) } || "",
            copy: copy_active ? "true" : "",
          ))
          newline
        end

        # Plain-text extraction mirroring `Markdown#post_process_html`'s
        # inline char-level tag strip (including its quote-awareness: a `>`
        # inside a quoted attribute value must not end the tag), so a
        # heading's title text is normalized identically on both the hook
        # path and the stock `post_process_html` path (see
        # `HeadingIds.assign`).
        private def strip_tags(html : String) : String
          String.build(html.bytesize) do |io|
            in_tag = false
            quote = nil.as(Char?)
            html.each_char do |c|
              if in_tag
                if quote
                  quote = nil if c == quote
                elsif c == '"' || c == '\''
                  quote = c
                elsif c == '>'
                  in_tag = false
                end
              elsif c == '<'
                in_tag = true
              else
                io << c
              end
            end
          end.strip
        end
      end

      # Syntax highlighter module for rendering markdown with highlighting support
      module SyntaxHighlighter
        extend self

        # Build-wide highlighting mode, set from `[highlight] mode` when the
        # build initializes. Read-only during rendering, so parallel render
        # fibers can consult it without synchronization.
        @@server_mode = false

        def server_mode=(value : Bool)
          @@server_mode = value
        end

        def server_mode? : Bool
          @@server_mode
        end

        # Global default for fence-level `linenos` (`[highlight]
        # line_numbers`), set from config when the build initializes.
        # Read-only during rendering, mirroring `@@server_mode`.
        @@default_line_numbers = false

        def default_line_numbers=(value : Bool)
          @@default_line_numbers = value
        end

        def default_line_numbers? : Bool
          @@default_line_numbers
        end

        # Global default for the fence-level copy button (`[highlight]
        # copy`), same lifecycle as `@@default_line_numbers`.
        @@default_copy = false

        def default_copy=(value : Bool)
          @@default_copy = value
        end

        def default_copy? : Bool
          @@default_copy
        end

        # Fingerprint of module-level state that changes rendered body HTML.
        def body_fingerprint : String
          String.build(3) do |io|
            io << (@@server_mode ? '1' : '0')
            io << (@@default_line_numbers ? '1' : '0')
            io << (@@default_copy ? '1' : '0')
          end
        end

        # Render markdown to HTML with syntax highlighting enabled
        # @param content - markdown content to render
        # @param highlight - whether to enable syntax highlighting for code blocks
        # @param safe - if true, raw HTML will not be passed through (replaced by comments)
        # @param smart - if true, markd's smart punctuation rewrites straight
        #   quotes/dashes/ellipses in Text nodes (code spans, raw HTML, and the
        #   \x00 placeholders the extension passes leave are untouched)
        # @param hooks - render-hook context (nil when no `templates/hooks/render-*`
        #   template is configured); when nil the renderer construction below is
        #   byte-identical to the pre-hooks code path.
        def render(content : String, highlight : Bool = true, safe : Bool = false, *, smart : Bool = false, tables_preprocessed : Bool = false,
                   hooks : Content::Processors::RenderHooks::HookRenderContext? = nil) : String
          # Pre-process tables before passing to markd (markd doesn't support
          # GFM tables). Markdown#render already converts tables before the
          # extension passes and passes `tables_preprocessed: true` to skip the
          # redundant per-page scan — the default stays for direct callers of
          # SyntaxHighlighter.render.
          processed_content = tables_preprocessed ? content : TableParser.process(content)

          options = Markd::Options.new(safe: safe, smart: smart)
          document = Markd::Parser.parse(processed_content, options)
          renderer = if hooks
                       HookedRenderer.new(options, highlight, @@server_mode, hooks)
                     else
                       HighlightingRenderer.new(options, highlight, @@server_mode)
                     end
          renderer.render(document)
        end

        # Check if content has code blocks that might benefit from highlighting
        def has_code_blocks?(content : String) : Bool
          content.includes?("```") || content.includes?("~~~")
        end

        # List of supported languages for highlight.js (common ones)
        SUPPORTED_LANGUAGES = Set.new(%w[
          bash c cpp csharp css crystal dart diff dockerfile elixir elm
          erlang go graphql groovy haskell html http ini java javascript
          json julia kotlin latex less lisp lua makefile markdown matlab
          nginx nim nix objectivec ocaml perl php plaintext powershell
          python r ruby rust scala scss shell sql swift toml typescript
          vim xml yaml zig
        ])

        # Check if a language is supported
        def language_supported?(lang : String) : Bool
          SUPPORTED_LANGUAGES.includes?(lang.downcase)
        end

        # Get CSS themes available for highlight.js
        THEMES = Set.new(%w[
          default a11y-dark a11y-light agate androidstudio an-old-hope
          arduino-light arta ascetic atom-one-dark atom-one-dark-reasonable
          atom-one-light brown-paper codepen-embed color-brewer dark
          devibeans docco far foundation github github-dark github-dark-dimmed
          googlecode gradient-dark gradient-light grayscale hybrid idea
          intellij-light ir-black isbl-editor-dark isbl-editor-light
          kimbie-dark kimbie-light lightfair lioshi magula mono-blue monokai
          monokai-sublime night-owl nnfx-dark nnfx-light nord obsidian ocean
          paraiso-dark paraiso-light panda-syntax-dark panda-syntax-light
          pojoaque purebasic qtcreator-dark qtcreator-light rainbow school-book
          shades-of-purple srcery stackoverflow-dark stackoverflow-light sunburst
          tokyo-night-dark tokyo-night-light tomorrow-night-blue
          tomorrow-night-bright vs vs2015 xcode xt256 zenburn
        ])

        # Check if a theme is valid
        def theme_valid?(theme : String) : Bool
          THEMES.includes?(theme.downcase)
        end
      end
    end
  end
end
