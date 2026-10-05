# Used-selector manifest for utility-CSS tools (`[build] write_stats`).
#
# Collects the tag names, classes and ids of every rendered HTML page and
# writes them as `hwaro_stats.json` at the project root, in the shape of
# Hugo's `hugo_stats.json`, so Tailwind (`@source`) and similar purgers can
# read one file instead of crawling the output:
#
#   {"htmlElements": {"tags": [...], "classes": [...], "ids": [...]}}
#
# Pages are scanned from the rendered string as they are written (one
# memchr-driven pass per page, merged under a mutex); nothing is re-read
# from disk.

require "html"
require "json"
require "./byte_scan"
require "./file_safe"

module Hwaro
  module Utils
    class HtmlStats
      FILE = "hwaro_stats.json"

      getter tags = Set(String).new
      getter classes = Set(String).new
      getter ids = Set(String).new
      @mutex = Mutex.new

      # Scan one rendered HTML document and merge what it uses.
      def add(html : String) : Nil
        tags = Set(String).new
        classes = Set(String).new
        ids = Set(String).new
        HtmlStats.scan(html, tags, classes, ids)
        @mutex.synchronize do
          @tags.concat(tags)
          @classes.concat(classes)
          @ids.concat(ids)
        end
      end

      # Fold a previously written stats file in (a partial build keeps the
      # selectors of the pages it did not re-render). A missing or malformed
      # file adds nothing.
      def merge_file(path : String) : Nil
        return unless File.file?(path)
        elements = JSON.parse(File.read(path))["htmlElements"]?
        return unless elements
        @mutex.synchronize do
          {"tags" => @tags, "classes" => @classes, "ids" => @ids}.each do |key, set|
            elements[key]?.try(&.as_a?).try(&.each { |v| v.as_s?.try { |s| set << s } })
          end
        end
      rescue JSON::ParseException | File::Error | IO::Error
      end

      def serialize : String
        @mutex.synchronize do
          String.build do |io|
            JSON.build(io, indent: "  ") do |json|
              json.object do
                json.field "htmlElements" do
                  json.object do
                    json.field "tags", @tags.to_a.sort!
                    json.field "classes", @classes.to_a.sort!
                    json.field "ids", @ids.to_a.sort!
                  end
                end
              end
            end
            io << '\n'
          end
        end
      end

      # Write `path` unless it already holds these bytes, so an unchanged
      # build keeps the file's mtime (and a watcher on it stays quiet).
      def write(path : String = FILE) : Nil
        content = serialize
        return if File.file?(path) && File.read(path) == content
        FileSafe.atomic_write(path, content)
      end

      # Raw-text elements: their bodies are not markup, so a `<` inside a
      # script (`a<b`) must not read as a tag.
      RAW_TEXT_TAGS = {"script", "style"}

      def self.scan(html : String, tags : Set(String), classes : Set(String), ids : Set(String)) : Nil
        bytes = html.to_slice
        n = bytes.size
        i = 0
        while lt = bytes.index('<'.ord.to_u8, i)
          i = lt + 1
          break if i >= n
          if bytes[i] == '!'.ord
            if i + 2 < n && bytes[i + 1] == '-'.ord && bytes[i + 2] == '-'.ord
              close = ByteScan.byte_index(html, "-->", i + 3)
              i = close ? close + 3 : n
            end
          elsif bytes[i].unsafe_chr.ascii_letter?
            start = i
            while i < n && tag_name_byte?(bytes[i])
              i += 1
            end
            name = html.byte_slice(start, i - start).downcase
            tags << name
            i = scan_attributes(html, bytes, i, classes, ids)
            if RAW_TEXT_TAGS.includes?(name)
              close = ByteScan.byte_index(html, "</#{name}", i) ||
                      ByteScan.byte_index(html, "</#{name.upcase}", i)
              i = close || n
            end
          end
        end
      end

      # Walks one start tag's attributes from `i`; returns the index just
      # past its `>` (or the end of input).
      private def self.scan_attributes(html : String, bytes : Bytes, i : Int32, classes : Set(String), ids : Set(String)) : Int32
        n = bytes.size
        while i < n
          b = bytes[i]
          return i + 1 if b == '>'.ord
          if b.unsafe_chr.ascii_whitespace? || b == '/'.ord
            i += 1
            next
          end
          start = i
          while i < n && !bytes[i].unsafe_chr.ascii_whitespace? && bytes[i] != '='.ord && bytes[i] != '>'.ord && bytes[i] != '/'.ord
            i += 1
          end
          attr = html.byte_slice(start, i - start).downcase
          while i < n && bytes[i].unsafe_chr.ascii_whitespace?
            i += 1
          end
          next unless i < n && bytes[i] == '='.ord
          i += 1
          while i < n && bytes[i].unsafe_chr.ascii_whitespace?
            i += 1
          end
          break if i >= n
          quote = bytes[i]
          if quote == '"'.ord || quote == '\''.ord
            vstart = i + 1
            vend = bytes.index(quote, vstart) || n
            i = vend + 1
          else
            vstart = i
            while i < n && !bytes[i].unsafe_chr.ascii_whitespace? && bytes[i] != '>'.ord
              i += 1
            end
            vend = i
          end
          next unless attr == "class" || attr == "id"
          value = html.byte_slice(vstart, vend - vstart)
          value = HTML.unescape(value) if value.includes?('&')
          if attr == "id"
            id = value.strip
            ids << id unless id.empty?
          else
            value.split { |cls| classes << cls }
          end
        end
        n
      end

      private def self.tag_name_byte?(b : UInt8) : Bool
        c = b.unsafe_chr
        c.ascii_alphanumeric? || c == '-' || c == ':' || c == '_' || c == '.'
      end
    end
  end
end
