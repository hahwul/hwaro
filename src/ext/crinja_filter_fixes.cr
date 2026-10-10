# Built-in Crinja filters whose results differed from Jinja2's, each
# re-registered after the original so it replaces it.

# `dictsort(reverse=true)` was accepted and ignored.
Crinja.filter({
  case_sensitive: false,
  by:             "key",
  reverse:        false,
}, :dictsort) do
  case_sensitive = arguments["case_sensitive"].truthy?
  direction = arguments["reverse"].truthy? ? -1 : 1
  index = arguments["by"].to_s == "value" ? 1 : 0

  target.to_a.sort { |a, b| Crinja::Filter.__compare(a[index], b[index], case_sensitive) * direction }
end

# `urlencode` follows Python's `quote`: a string keeps `/` (and `~`), so
# `{{ path | urlencode }}` stays a path instead of becoming `%2Fa%2Fb`; a
# mapping or list of pairs encodes a query string with `+` for spaces.
module Crinja::Filter
  def self.__url_quote(string : String, for_qs : Bool) : String
    String.build do |io|
      string.each_byte do |byte|
        char = byte.unsafe_chr
        if char.ascii_alphanumeric? || char.in?('_', '.', '-', '~') || (char == '/' && !for_qs)
          io << char
        elsif char == ' ' && for_qs
          io << '+'
        else
          io << '%' << byte.to_s(16, upcase: true).rjust(2, '0')
        end
      end
    end
  end
end

Crinja.filter(:urlencode) do
  if target.iterable?
    target.map do |item|
      if item.iterable? && item.size == 2
        "#{Crinja::Filter.__url_quote(item[0].to_s, true)}=#{Crinja::Filter.__url_quote(item[1].to_s, true)}"
      else
        Crinja::Filter.__url_quote(item.to_s, true)
      end
    end.join("&")
  else
    Crinja::Filter.__url_quote(target.to_s, false)
  end
end

# `indent(width=4, first=false, blank=false)` as in Jinja2: blank lines are
# not indented unless `blank=true`, `first=true` indents the first line
# (upstream only knew the old `indentfirst` name, still accepted), and a
# string width is used as the indent itself.
Crinja.filter({width: 4, first: false, blank: false, indentfirst: false}, :indent) do
  width = arguments["width"]
  indention = width.string? ? width.as_s : " " * Math.max(width.to_i, 0)
  lines = (target.to_s + "\n").lines

  result = if arguments["blank"].truthy?
             lines.join("\n" + indention)
           else
             lines.map_with_index { |line, i| i == 0 || line.empty? ? line : indention + line }.join("\n")
           end
  arguments["first"].truthy? || arguments["indentfirst"].truthy? ? indention + result : result
end

# `wordcount` counts runs of word characters (Python's `\w+`). Upstream split
# on a few separators and counted the pieces, so an empty string had one
# word and punctuation-only text counted as words.
Crinja.filter(:wordcount) do
  target.to_s.scan(/[\p{L}\p{N}_]+/).size
end
