# `wordwrap`, rewritten after Python's textwrap (what Jinja2 uses).
#
# Upstream cut every line at exactly `width` characters, mid-word, and
# looped forever — hanging the build — on `wordwrap(0)` or on a word longer
# than the width with `break_long_words=false`. Now lines break between
# words, a word longer than the width is split only when break_long_words
# is set, whitespace at wrapped line edges is dropped, and a width below 1
# is an error, as in Jinja2.
#
# ponytail: no break_on_hyphens splitting (accepted, ignored); a hyphenated
# word straddling the width moves whole to the next line instead.
Crinja.filter({width: 79, break_long_words: true, wrapstring: nil, break_on_hyphens: true}, :wordwrap) do
  width = arguments["width"].to_i
  raise ArgumentError.new("wordwrap() width must be > 0, got #{width}") if width <= 0
  break_long_words = arguments["break_long_words"].truthy?
  wrapstring = arguments.fetch("wrapstring", "\n").to_s

  target.to_s.lines.join(wrapstring) do |line|
    Crinja::Util.__wrap_line(line, width, break_long_words).join(wrapstring)
  end
end

module Crinja::Util
  # textwrap.TextWrapper#_wrap_chunks with drop_whitespace=True.
  def self.__wrap_line(text : String, width : Int32, break_long_words : Bool) : Array(String)
    chunks = text.split(/(\s+)/).reject!(&.empty?).reverse!
    lines = [] of String

    until chunks.empty?
      chunks.pop if chunks.last.blank? && !lines.empty?
      current = [] of String
      length = 0
      while (chunk = chunks.last?) && length + chunk.size <= width
        current << chunks.pop
        length += chunk.size
      end

      if (chunk = chunks.last?) && chunk.size > width
        if break_long_words
          space_left = width - length
          current << chunk[0, space_left]
          chunks[-1] = chunk[space_left..]
        elsif current.empty?
          current << chunks.pop
        end
      end

      current.pop if (last = current.last?) && last.blank?
      lines << current.join unless current.empty?
    end

    lines
  end
end
