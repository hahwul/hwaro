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

  # markupsafe semantics: a safe target (or a safe `end`) keeps its markup,
  # and the appended `end` — the only inserted text, only on the cut branch —
  # is preserved if safe and escaped if plain (`Markup.append_suffix`). A whole
  # (untruncated) safe string is returned as is; off the switch everything is
  # a plain concat, byte-identical.
  safe_target = Crinja::Markup.active?(env) && Crinja::Markup.safe?(target)
  s = target.to_s
  if s.size - leeway <= length
    Crinja::Value.new(safe_target ? Crinja::Markup.derived(s, target) : s)
  else
    trimmed = Hwaro::Utils::TextUtils.safe_prefix(s, length - append.size)
    unless arguments["killwords"].truthy?
      cut = trimmed.rindex(' ')
      trimmed = trimmed[0, cut] if cut
    end
    Crinja::Markup.append_suffix(env, trimmed, target, arguments["end"])
  end
end

# `format` hands numbers to `sprintf` unwrapped. Upstream passed the
# `Crinja::Value`s themselves, so every float conversion (`"%.2f" |
# format(price)`) raised `Expected a float` and failed the page.
Crinja.filter(:format) do
  sprintf target.to_s, arguments.varargs.map { |arg| arg.number? ? arg.as_number : arg }
end

# `replace` on a number, boolean or none replaces in its text, as Jinja2
# does. Upstream required a string and raised "Unexpected type in Crinja
# value", so `{{ page.extra.price | replace(".", ",") }}` failed the page.
# An undefined target still raises, as before.
Crinja.filter({old: Crinja::UNDEFINED, new: Crinja::UNDEFINED, count: nil}, :replace) do
  search = arguments["old"].to_s
  replace = arguments["new"]
  count = arguments["count"]

  if count.raw.nil?
    source = target.raw.is_a?(String | Crinja::SafeString | Crinja::Undefined) ? target.as_s_or_safe : target.to_s
    source.gsub(search, replace)
  else
    string = target.to_s
    count.to_i.times do
      running = false
      string = string.sub(search) { running = true; replace }
      break unless running
    end
    string
  end
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

# `int` converts to Int64 (as Crinja's integers are) and, like Python, reads
# a string as an integer first and as a float after (`"1e3"` is 1000). It
# went through Int32: `"3000000000" | int` gave the default 0, and
# `3000000000.0 | int` (a large float from front matter or data) failed the
# build with "Arithmetic overflow", as did NaN, which Python turns into the
# default. A float outside Int64 (or infinite) also gives the default, and
# the default is returned as given, as in Jinja2 (`int(3000000000)` went
# through Int32 too and raised "Arithmetic overflow").
#
# A string is read with Python's int(string, base) rules: a `0b`/`0o`/`0x`
# prefix only in its own base (or base 0, which picks the base from it),
# single underscores between digits (`"1_000"`, also in the float reading),
# and a base outside 0 and 2..36 falls through to the float reading. Crystal's
# `to_i64?(base, prefix: true)` read any prefix in any base (`"0x10" | int`
# gave 16, Jinja2 0), refused underscores, and raised on `base=0`.
module Crinja::Filter
  def self.__float_to_int(float : Float64) : Int64?
    float.to_i64 if float.finite? && float > Int64::MIN.to_f64 && float < Int64::MAX.to_f64
  end

  def self.__py_int(string : String, base : Int) : Int64?
    return unless base == 0 || 2 <= base <= 36
    digits = string.strip
    sign = ""
    if digits.starts_with?('-') || digits.starts_with?('+')
      sign = "-" if digits.starts_with?('-')
      digits = digits[1..]
    end
    radix = case digits.starts_with?('0') && digits[1]?.try(&.downcase)
            when 'x' then 16
            when 'o' then 8
            when 'b' then 2
            end
    if radix && (base == 0 || base == radix)
      base = radix
      # An underscore may follow the prefix itself (`0x_ff`).
      digits = digits[2..].lchop('_')
    elsif base == 0
      base = 10
      # Base 0 reads an unprefixed number as decimal, without leading zeros.
      return if digits.starts_with?('0') && digits.each_char.any? { |char| char != '0' && char != '_' }
    end
    return if digits.empty? || !digits.each_char.all? { |char| char.ascii_alphanumeric? || char == '_' }
    return unless __underscores_between?(digits, &.ascii_alphanumeric?)
    "#{sign}#{digits.delete('_')}".to_i64?(base, whitespace: false)
  end

  # Python's float(): underscores only between two digits.
  def self.__py_float(string : String) : Float64?
    text = string.strip
    return text.to_f? unless text.includes?('_')
    text.delete('_').to_f? if __underscores_between?(text, &.ascii_number?)
  end

  # Every `_` in *text* sits between two characters that pass the block
  # (so never first, last, or next to another `_`).
  private def self.__underscores_between?(text : String, & : Char -> Bool) : Bool
    return true unless text.includes?('_')
    chars = text.chars
    chars.each_with_index do |char, i|
      next unless char == '_'
      return false unless 0 < i < chars.size - 1 && yield(chars[i - 1]) && yield(chars[i + 1])
    end
    true
  end
end

Crinja.filter({default: 0, base: 10}, :int) do
  raw = target.raw
  raw = raw.to_s if raw.is_a?(Crinja::SafeString)
  result = case raw
           when Bool   then raw ? 1 : 0
           when String then Crinja::Filter.__py_int(raw, arguments["base"].to_i) || Crinja::Filter.__py_float(raw).try { |float| Crinja::Filter.__float_to_int(float) }
           when Int    then raw
           when Float  then Crinja::Filter.__float_to_int(raw.to_f64)
           end
  result ? Crinja::Value.new(result) : arguments["default"]
end

# `min` / `max` (Jinja2 built-ins Crinja lacks): the first smallest / largest
# item, compared like `sort` (strings case-insensitively unless
# `case_sensitive=true`), by an `attribute=` path (dotted, as in `sort`) when
# given (an undefined one is none, as in `sort`); a mapping compares its keys. An empty or undefined sequence gives
# undefined; items that cannot be compared raise a template error.
module Crinja::Filter
  def self.__extreme(target : Value, arguments : Arguments, sign : Int32) : Value
    return Value.new(Undefined.new) if target.undefined?
    attribute = arguments["attribute"]
    case_sensitive = arguments["case_sensitive"].truthy?
    best = nil
    raw = target.raw
    # A mapping iterates its keys, as in Python.
    items = raw.is_a?(Hash) ? raw.keys : target.to_a
    items.each do |item|
      key = attribute.none? || attribute.undefined? ? item : __attr_path(attribute, item)
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

# `filesizeformat` as Jinja2 writes it: `1 Byte` (not `1 Bytes`), and the
# exa-, zetta- and yotta- units. Upstream's table stopped at peta-, so a size
# of a thousand petabytes or more (`1000000000000000000 | filesizeformat`)
# fell off the end and printed `none`.
module Crinja::Filter
  FILESIZE_PREFIXES        = {"kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"}
  FILESIZE_BINARY_PREFIXES = {"KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"}

  def self.__filesizeformat(bytes : Float64, binary : Bool) : String
    base = binary ? 1024.0 : 1000.0
    return "1 Byte" if bytes == 1
    # Python's int(): truncated, and no sign on zero (`-0.5` is `0 Bytes`).
    return "#{sprintf("%.0f", bytes.trunc.abs < 1 ? 0.0 : bytes.trunc)} Bytes" if bytes < base
    prefixes = binary ? FILESIZE_BINARY_PREFIXES : FILESIZE_PREFIXES
    unit = base
    prefixes.each do |prefix|
      unit *= base
      return "#{sprintf("%.1f", base * bytes / unit)} #{prefix}" if bytes < unit
    end
    "#{sprintf("%.1f", base * bytes / unit)} #{prefixes.last}"
  end
end

Crinja.filter({binary: false}, :filesizeformat) do
  Crinja::Filter.__filesizeformat(target.to_f.to_f64, arguments["binary"].truthy?)
end

# `groupby` gives Jinja2's groups: a list of (grouper, list) pairs whose
# `grouper` and `list` attributes name the two halves. Upstream returned a
# mapping, so the documented Jinja2 loop `{% for group in posts |
# groupby("year") %}{{ group.grouper }}` failed the build ("group.grouper is
# undefined") and `(posts | groupby("year"))[0]` was empty. Groups keep the
# order their first item appears in (hwaro's, not sorted as in Jinja2: a
# sort would fail on a field some items lack), and `for key, items in …`
# unpacks a group as before.
class Crinja::GroupTuple < Crinja::Tuple
  def crinja_attribute(attr : Crinja::Value) : Crinja::Value
    case attr.to_s
    when "grouper" then self[0]
    when "list"    then self[1]
    else                Crinja::Value.new(Crinja::Undefined.new(attr.to_s))
    end
  end
end

Crinja.filter({attribute: Crinja::UNDEFINED}, :groupby) do
  attribute = arguments["attribute"]
  groups = Crinja::Dictionary.new
  target.each do |item|
    key = Crinja::Value.new(Crinja::Resolver.resolve_dig(attribute, item))
    (groups[key] ||= Crinja::Value.new([] of Crinja::Value)).as_a << item
  end
  groups.map { |key, list| Crinja::Value.new(Crinja::GroupTuple.new([key, list] of Crinja::Value)) }
end

# `pprint` prints the whole value. Upstream never flushed its PrettyPrint,
# which holds back everything after the first group break, so
# `{{ {"k": "v", "n": 2} | pprint }}` printed `{"k" =>`; and an undefined
# value printed its object address (`#<Crinja::Undefined:0x…`), which
# differs between builds. It prints `Undefined`, as Jinja2's does.
Crinja.filter({verbose: false}, :pprint) do
  if target.undefined?
    "Undefined"
  else
    String.build do |io|
      printer = Crinja::PrettyPrint.new(io, verbose: arguments["verbose"].truthy?)
      target.pretty_print(printer)
      printer.flush
    end
  end
end

# An undefined value is an empty sequence (and empty text) to `join`,
# `reverse`, `list`, `batch`, `slice` and `replace`, as in Jinja2. They
# raised instead, so `{{ page.extra.authors | join(", ") }}` failed the
# build on every page without that field (with a nameless
# " must be a sequence to join it"). Undefined targets only: `none` and
# other non-sequences still raise.
module Crinja::Filter
  UNDEFINED_AS_EMPTY = {"join", "reverse", "list", "batch", "slice", "replace"}

  def self.__undefined_as_empty(filter : Callable::Instance) : Callable::Instance
    inner = filter.proc
    empty = filter.name == "replace" ? Value.new("") : Value.new([] of Value)
    proc = ->(arguments : Arguments) do
      if arguments.target.try(&.undefined?)
        arguments = Arguments.new(arguments.env, arguments.varargs, arguments.kwargs, arguments.defaults, empty)
      end
      inner.call(arguments)
    end
    Callable::Instance.new(proc, filter.defaults, filter.name)
  end
end

Crinja::Filter::Library.defaults.map! do |filter|
  if filter.is_a?(Crinja::Callable::Instance) && Crinja::Filter::UNDEFINED_AS_EMPTY.includes?(filter.name)
    Crinja::Filter.__undefined_as_empty(filter)
  else
    filter
  end
end
