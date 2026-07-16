# Pandoc-style `{#id .class key=val}` attribute blocks (F9) — v1 scope is
# headings and inline images.
#
# The grammar is a whitespace-separated token list (commas are NOT
# separators, unlike fence options): `#id`, `.class`, and `key=value` /
# `key="quoted value"` tokens in any order/count. Any single invalid token
# invalidates the WHOLE block — the source text is then left untouched by
# the caller, exactly as if the block had never been written. Parsing never
# raises: it's regex-driven with explicit fallbacks, no `to_i`/indexing that
# could throw.
#
# Because the block can appear inside markdown that Markd will still parse
# (a heading line, an image's trailing text), it can't be resolved directly
# in `preprocess` — Markd would see raw `{...}` text and pass it through
# untouched, or (worse) mangle it. So — mirroring the existing `{#id}` /
# `<!--HID:...-->` mechanism — a block that parses successfully is replaced
# by a `<!--HATTR:HEXPAYLOAD-->` comment (hex-encoded so the payload can
# freely contain `-->`-hostile bytes without breaking the HTML comment),
# which survives Markd's render untouched and is resolved into real
# attributes by `postprocess_attributes` in `markdown_extensions.cr`.
require "html"

module Hwaro
  module Content
    module Processors
      module MarkdownAttributes
        extend self

        # A successfully parsed `{...}` attribute block.
        # `attrs` preserves insertion order (last-value-wins per key), so
        # HTML generation is deterministic across runs.
        record Parsed, id : String?, classes : Array(String), attrs : Array({String, String})

        # One token: `#id`, `.class`, or `key=value`/`key="quoted value"`.
        # `\G` anchors each successive match at the end of the previous one
        # (via the `pos` argument to `match`), so a run of intervening
        # whitespace is consumed but any OTHER leftover text — a token that
        # matches none of the three forms — breaks the chain and shows up
        # as residue, which invalidates the whole block.
        #
        # Capture groups: 1 = `#id` token (with `#`), 2 = `.class` token
        # (with `.`), 3 = kv key, 4 = kv value (quotes included if quoted),
        # 5 = kv value's inner text when quoted (nil when bare).
        TOKEN_RE = /\G\s*(?:(\#[A-Za-z][\w:-]*)|(\.[A-Za-z_][\w-]*)|([A-Za-z_][\w-]*)=("([^"{}]*)"|[^\s"'`=<>{}]+))/

        # Parses the inside of a `{...}` block (braces already stripped).
        # Returns `nil` when the block is empty, contains a token matching
        # none of the three forms, or has unconsumed non-whitespace residue
        # between/after valid tokens.
        def parse(block_inner : String) : Parsed?
          id : String? = nil
          classes = [] of String
          attrs = [] of {String, String}
          found_any = false

          pos = 0
          len = block_inner.size
          while pos < len
            m = TOKEN_RE.match(block_inner, pos)
            break unless m
            new_pos = m.end
            break unless new_pos > pos
            pos = new_pos
            found_any = true

            if id_token = m[1]?
              id = id_token[1..] # strip leading '#'
            elsif class_token = m[2]?
              add_class(classes, class_token[1..]) # strip leading '.'
            elsif key = m[3]?
              value = m[5]? || m[4]
              case key
              when "id"
                id = value
              when "class"
                add_class(classes, value)
              else
                attrs.reject! { |(k, _)| k == key }
                attrs << {key, value}
              end
            end
          end

          residue = block_inner[pos..]
          return unless residue.strip.empty?
          return unless found_any

          Parsed.new(id: id, classes: classes, attrs: attrs)
        end

        private def add_class(classes : Array(String), name : String) : Nil
          classes << name unless classes.includes?(name)
        end

        # Hex-encodes `block_inner` (the RAW, still-unparsed `{...}` contents)
        # so it can ride through Markd's render inside an HTML comment
        # without needing its own comment-safe escaping — hex is immune to
        # `-->`/`<`/`&` entirely.
        def encode(block_inner : String) : String
          block_inner.to_slice.hexstring
        end

        # Inverse of `encode`. `nil` on any malformed (odd-length / non-hex)
        # payload — never raises.
        def decode(payload : String) : String?
          bytes = payload.hexbytes?
          return unless bytes
          str = String.new(bytes)
          # Author-typed `<!--HATTR:ff-->` comments reach here in non-safe
          # mode; invalid UTF-8 would make the caller's Regex#match raise, so
          # reject it (upholding the "never raises" contract of `parse`).
          return unless str.valid_encoding?
          str
        end

        # Merges `id` (replace-or-append) and `classes`
        # (merge-into-existing-or-add) into an existing heading tag's
        # attribute string (e.g. ` class="foo"`, or `""` when the tag had
        # no attributes), matching `postprocess_heading_ids`'s formatting
        # byte-for-byte for the id case.
        def apply_to_tag_attrs(existing_attrs : String, parsed : Parsed) : String
          merge_attrs(existing_attrs, parsed)
        end

        # Merges `parsed` into an `<img ...` tag's opening portion (up to,
        # but NOT including, its `/>`/`>` closer — the caller re-appends the
        # original closer so self-closing style is preserved untouched).
        def apply_to_img(img_open : String, parsed : Parsed) : String
          merge_attrs(img_open, parsed)
        end

        # `(?<![\w-])` guards keep `data-id=`/`data-class=` from counting
        # as the element's own id/class.
        ID_ATTR_RE    = /(?<![\w-])id\s*=\s*"[^"]*"/i
        ID_PRESENT_RE = /(?<![\w-])id\s*=/i
        CLASS_ATTR_RE = /(?<![\w-])class\s*=\s*"([^"]*)"/i

        # Shared merge logic for both entry points above: id and classes get
        # their own dedicated attribute; every other `key=value` pair is
        # replaced in place when the tag already carries that attribute, or
        # appended when it doesn't ("source-order replace-or-append").
        # Every emitted value is HTML-escaped — this is the only place raw
        # `{...}` payload text reaches tag output, so nothing here may trust
        # it verbatim.
        private def merge_attrs(attrs : String, parsed : Parsed) : String
          result = attrs

          if id = parsed.id
            escaped_id = HTML.escape(id)
            result = if result.matches?(ID_PRESENT_RE)
                       result.sub(ID_ATTR_RE, %(id="#{escaped_id}"))
                     else
                       %(#{result.rstrip} id="#{escaped_id}")
                     end
          end

          unless parsed.classes.empty?
            escaped_classes = parsed.classes.map { |c| HTML.escape(c) }.join(" ")
            result = if class_match = result.match(CLASS_ATTR_RE)
                       merged = "#{class_match[1]} #{escaped_classes}".strip
                       result.sub(CLASS_ATTR_RE, %(class="#{merged}"))
                     else
                       %(#{result.rstrip} class="#{escaped_classes}")
                     end
          end

          parsed.attrs.each do |key, value|
            escaped_value = HTML.escape(value)
            key_re = /\b#{Regex.escape(key)}\s*=\s*"[^"]*"/i
            result = if result.matches?(key_re)
                       result.sub(key_re, %(#{key}="#{escaped_value}"))
                     else
                       %(#{result.rstrip} #{key}="#{escaped_value}")
                     end
          end

          result
        end
      end
    end
  end
end
