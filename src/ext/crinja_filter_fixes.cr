# Built-in Crinja filters whose results differed from Jinja2's, each
# re-registered after the original so it replaces it, and the Jinja2
# built-ins Crinja lacks (`min`, `max`).

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

# `truncate` as in Jinja2: a string within `length + leeway` is returned
# whole, and without `killwords` the cut falls back to the last space only
# when there is one. Upstream returned a bare `...` for any cut text with no
# space (a long word, a URL, CJK prose) and for any `length` up to the
# leeway (`"Hello" | truncate(3)`), dropping the text entirely.
Crinja.filter({length: 255, killwords: false, end: "...", leeway: nil}, :truncate) do
  length = arguments["length"].to_i
  append = arguments["end"].to_s
  raise "expected length >= #{append.size}, got #{length}" if length < append.size
  leeway = arguments.fetch("leeway") { env.policies.fetch("truncate.leeway", 5) }.to_i
  raise "expected leeway >= 0, got #{leeway}" if leeway < 0

  s = target.to_s
  if s.size - leeway <= length
    s
  else
    trimmed = s[0, length - append.size]
    unless arguments["killwords"].truthy?
      cut = trimmed.rindex(' ')
      trimmed = trimmed[0, cut] if cut
    end
    trimmed + append
  end
end

# `format` hands numbers to `sprintf` unwrapped. Upstream passed the
# `Crinja::Value`s themselves, so every float conversion (`"%.2f" |
# format(price)`) raised `Expected a float` and failed the page.
Crinja.filter(:format) do
  sprintf target.to_s, arguments.varargs.map { |arg| arg.number? ? arg.as_number : arg }
end

# `float` / `int` convert numbers and booleans as Python does. Upstream only
# knew strings (and floats, for `int`), so `{{ 3 | float }}` printed `0.0`
# and `{{ true | int }}` printed `0`.
Crinja.filter({default: 0.0}, :float) do
  case raw = target.raw
  when Number then raw.to_f
  when Bool   then raw ? 1.0 : 0.0
  else
    (raw.to_f? if raw.is_a?(String)) || arguments["default"].to_f
  end
end

Crinja.filter({default: 0, base: 10}, :int) do
  raw = target.raw
  raw = raw.to_s if raw.is_a?(Crinja::SafeString)
  result = case raw
           when Bool   then raw ? 1 : 0
           when String then raw['.']? ? raw.to_f?.try(&.to_i) : raw.to_i?(arguments["base"].to_i, prefix: true)
           when Int    then raw
           when Float  then raw.to_i
           end
  result ? Crinja::Value.new(result) : arguments["default"].to_i
end

# `min` / `max` (Jinja2 built-ins Crinja lacks): the first smallest / largest
# item, compared like `sort` (strings case-insensitively unless
# `case_sensitive=true`), by an `attribute=` path (dotted, as in `sort`) when
# given. An empty or undefined sequence gives undefined; items that cannot be
# compared raise a template error.
module Crinja::Filter
  def self.__extreme(target : Value, arguments : Arguments, sign : Int32) : Value
    return Value.new(Undefined.new) if target.undefined?
    attribute = arguments["attribute"]
    case_sensitive = arguments["case_sensitive"].truthy?
    best = nil
    target.to_a.each do |item|
      key = attribute.none? ? item : __attr_path(attribute, item)
      best = {key, item} if best.nil? || __compare(key, best[0], case_sensitive) * sign > 0
    end
    best ? best[1] : Value.new(Undefined.new)
  rescue ex : ArgumentError
    raise TypeError.new(ex.message)
  end
end

Crinja.filter({case_sensitive: false, attribute: nil}, :min) do
  Crinja::Filter.__extreme(target, arguments, -1)
end

Crinja.filter({case_sensitive: false, attribute: nil}, :max) do
  Crinja::Filter.__extreme(target, arguments, 1)
end
