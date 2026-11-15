# HTML autoescape (`[templates] autoescape`), with Jinja2's `Markup` rules.
#
# Crinja escapes a printed value unless it is a `SafeString`, and decides per
# template from its file name (`Config::Autoescape`). What it lacked, and
# what this file adds:
#
#   * `.jinja2` is stripped like `.jinja`/`.j2` before the extension is read
#     (`page.json.jinja2` is JSON, not an unknown type);
#   * a template can opt out of escaping whatever its name says
#     (`Template#__no_autoescape`): hwaro sets it on templates whose output
#     is text — `[[content.generate]]` specs, the JSON feed;
#   * safety survives the string operations Jinja2 keeps it through, and
#     never appears where Jinja2 would not give it. With autoescape on:
#     - `upper lower capitalize center indent trim truncate truncate_words
#       replace regex_replace format` of a safe value stay safe, and the text
#       they insert (`truncate`'s `end`, `replace`'s `new` but not `old`, as
#       in markupsafe, `format`'s arguments, …) is escaped;
#     - `string` keeps a safe value safe and no longer escapes a plain one
#       (it went through the escaping finalizer, so `| string` printed `&amp;`
#       twice);
#     - `join` escapes a separator that is not safe (items already were);
#     - `urlize` escapes the text it links (it returned it raw, marked safe);
#     - `a ~ b` and string `a + b` with a safe operand escape the other one
#       and are safe; with none they stay plain and print escaped;
#     - a `{% filter %}` block's body reaches the filter as safe markup and a
#       plain result is escaped (`{% filter striptags %}` decoded entities
#       and printed the text raw).
#     With autoescape off every one of them behaves exactly as before.
#
# The hwaro filters that build HTML or escape (`markdownify`, `xml_escape`,
# `tojson`/`jsonify`, `safe`, `default`, `strip_html`) follow the same rules
# in content/processors/filters/.

# HTML hwaro rendered (`content`, summaries, `toc`, hook `text`, the feed
# `content` — `Utils::CrinjaUtils.html_value`) is safe, but `| e` and
# `| escape` on it still escape it, as they did before autoescape: a feed
# template's `{{ p.summary | escape | xml_escape }}` and `{{ content | e }}`
# show the markup as text. Any other safe value (a capture, a macro result,
# `| safe`, pre-escaped text such as a hook `destination`) passes `| e`
# unchanged, as in Jinja2. The mark means "a String in 0.x", so it survives
# what 0.x derived as a String: a slice or character of a marked value, the
# keep-safe filters, `truncate`, `replace`, `~`/`+`/`append` with a marked
# operand (`SafeString#derive`, `Markup.derived`), and `markdownify`/`tojson`
# output. What 0.x already made a SafeString (`| e`, `| safe`, captures,
# macros, `join`, `urlize`) stays unmarked.
struct Crinja::SafeString
  @__rendered_html = false

  def initialize(@string : String, @plain_value : Bool, @__rendered_html : Bool)
  end

  def rendered_html? : Bool
    @__rendered_html
  end

  # A safe `string` derived from this one (a slice, a character, a filter
  # result). It keeps the mark: anything 0.x derived from `content` was a
  # String too, so `{{ content[:300] | e }}` and `{{ page.summary |
  # truncate(200) | escape }}` still escape.
  def derive(string : String) : SafeString
    SafeString.new(string, false, @__rendered_html)
  end

  # Upstream slices a SafeString into a new, unmarked one.
  def [](*args)
    result = previous_def
    result.is_a?(SafeString) ? derive(result.to_s) : result
  end

  def []?(*args)
    result = previous_def
    result.is_a?(SafeString) ? derive(result.to_s) : result
  end

  # The struct hash as it was before the mark existed (`@string`, then
  # `@plain_value`), so `content` and the equal `content | safe` are one key.
  # It must not drop `@plain_value` or hash like a String: `unique`, dict
  # keys and `groupby` would then fold a SafeString into the equal String
  # and change what `autoescape = false` sites print.
  def hash(hasher)
    hasher = @string.hash(hasher)
    @plain_value.hash(hasher)
  end
end

# Under autoescape the HTML hwaro renders reaches templates as a SafeString
# where it used to be a String. A SafeString behaves as its string wherever
# upstream only knew String: first/last, indexing, iteration (`for`, `list`,
# `batch`, `sort`, …). The characters it yields are plain Strings, as a
# String's are. Upstream bodies (lib/crinja/src/runtime/value.cr), copied
# because `previous_def` on the generic-iterator overload trips a compiler
# bug; the only change is `String` → `String, SafeString` (and `to_s`). No
# other ext file patches these methods.
struct Crinja::Value
  def [](index : Int) : Value
    case object = @raw
    when Indexable
      Value.new object[index]
    when String, SafeString
      Value.new object.to_s[index].to_s
    else
      raise TypeError.new(self, "expected Array for #[](index : Int), not #{object.class}")
    end
  end

  def first
    case object = @raw
    when Dictionary
      Value.new(Crinja::Tuple.new(object.first_key, object.first_value))
    when Iterable
      Value.new object.first
    when String, SafeString
      Value.new object.to_s[0, 1]
    else
      raise TypeError.new(self, "expected Iterable, Hash or String for #first, not #{object.class}")
    end
  end

  def last
    object = @raw

    if object.responds_to?(:last)
      Value.new object.last
    elsif object.is_a?(String | SafeString)
      Value.new object.to_s[-1, 1]
    else
      raise TypeError.new(self, "expected Enumerable or String for #last, not #{object.class}")
    end
  end

  def raw_each : ::Iterator
    case object = @raw
    when Hash
      HashTupleIterator.new(object.each)
    when Iterable(Value)
      RawIterator.new(object.each)
    when Iterable
      object.each
    when ::Iterator(Value)
      RawIterator.new(object)
    when ::Iterator
      object
    when String, SafeString
      object.to_s.each_char.map(&.to_s)
    when StrictUndefined
      raise TypeError.new(self, "can't iterate over undefined")
    when Undefined
      ([] of Nil).each
    else
      raise TypeError.new(self, "#{object.class} is not iterable")
    end
  end

  def raw_each(&)
    case object = @raw
    when Hash
      object.each { |key, value| yield Crinja::Tuple.from({key, value}) }
    when Iterable(Value), ::Iterator(Value)
      object.each { |value| yield value.as(Value).raw }
    when Iterable, ::Iterator
      object.each { |value| yield value }
    when String, SafeString
      object.to_s.each_char { |char| yield char.to_s }
    when StrictUndefined
      raise TypeError.new(self, "can't iterate over undefined")
    when Undefined
    else
      raise TypeError.new(self, "#{object.class} is not iterable")
    end
  end
end

Crinja.filter(:escape) do
  raw = target.raw
  if raw.is_a?(Crinja::SafeString) && !raw.rendered_html?
    raw
  else
    Crinja::SafeString.escape(raw.to_s)
  end
end

module Crinja::Markup
  extend self

  # Bytes `HTML.escape` replaces: `& < > " '`.
  SPECIAL = begin
    table = StaticArray(Bool, 256).new(false)
    "&<>\"'".each_byte { |byte| table[byte] = true }
    table
  end

  private ONES  = 0x0101010101010101_u64
  private HIGHS = 0x8080808080808080_u64

  # HTML-escaped `text` — `HTML.escape`'s bytes, and the same String when
  # there is nothing to escape (the common case: no copy). Every printed
  # plain string goes through here, so the scan reads eight bytes at a time:
  # `x ^ (b * ONES)` has a zero byte exactly where `x` holds byte `b`, and
  # `(y - ONES) & ~y & HIGHS` is non-zero exactly when `y` has a zero byte.
  def escape(text : String) : String
    bytes = text.to_unsafe
    size = text.bytesize
    i = 0
    # `i <= size - 8`, not `i + 8 <= size`: the latter overflows Int32 for a
    # string within 8 bytes of 2 GiB. `size - 8` is negative below 8 bytes,
    # so the word loop is simply skipped and the tail loop runs.
    while i <= size - 8
      word = (bytes + i).as(UInt64*).value
      return HTML.escape(text) if zero_byte?(word ^ (0x26_u64 &* ONES)) || zero_byte?(word ^ (0x3C_u64 &* ONES)) ||
                                  zero_byte?(word ^ (0x3E_u64 &* ONES)) || zero_byte?(word ^ (0x22_u64 &* ONES)) ||
                                  zero_byte?(word ^ (0x27_u64 &* ONES))
      i += 8
    end
    while i < size
      return HTML.escape(text) if SPECIAL.unsafe_fetch(bytes[i])
      i += 1
    end
    text
  end

  @[AlwaysInline]
  private def zero_byte?(word : UInt64) : Bool
    ((word &- ONES) & ~word & HIGHS) != 0
  end

  # A value as markup: a safe value as written, anything else escaped.
  def escape(value : Value) : String
    raw = value.raw
    raw.is_a?(SafeString) ? raw.to_s : escape(value.to_s)
  end

  def safe?(value : Value?) : Bool
    !value.nil? && value.raw.is_a?(SafeString)
  end

  # Whether `value` is HTML hwaro rendered (see `SafeString#derive`).
  def marked?(value : Value?) : Bool
    return false if value.nil?
    raw = value.raw
    raw.is_a?(SafeString) && raw.rendered_html?
  end

  # A safe result built from `sources`: it carries the rendered-HTML mark
  # when any of them does.
  def derived(string : String, *sources : Value?) : SafeString
    SafeString.new(string, false, sources.any? { |source| marked?(source) })
  end

  # Whether `[templates] autoescape` is on for this environment (the site
  # switch), independent of a `{% autoescape %}` tag. `configure_autoescape`
  # sets `default_for_string` to the switch, so an OFF-mode build never takes
  # the Markup code paths even inside a `{% autoescape true %}` block — its
  # output stays byte-identical to the pre-autoescape engine.
  #
  # Inside a text render (`Crinja#__text_render`: a JSON/text output, a
  # `[[content.generate]]` spec) it is false, so the engine there behaves
  # exactly as with the switch off.
  def enabled?(env : Crinja) : Bool
    switch?(env) && !env.__text_render
  end

  # The site switch alone.
  def switch?(env : Crinja) : Bool
    env.config.autoescape.default_for_string
  end

  # Whether printed values are being escaped right here: the switch is on AND
  # the current context escapes (a `{% autoescape false %}` block turns it
  # off). Every Markup filter/operator rule keys off this.
  def active?(env : Crinja) : Bool
    enabled?(env) && env.context.autoescape?
  end

  # Whether a producer (`join`, `urlize`, a macro, a recursive loop) that
  # stringified its inputs WITHOUT escaping may still mark its result safe.
  # It may when the switch is off (byte-identical to the old engine, which
  # always marked these safe) or when the current context escapes (the inputs
  # were escaped). It may NOT inside a `{% autoescape false %}` block with the
  # switch on: there the result is unescaped text, so printing it elsewhere
  # must escape it. (Same shape as the `{% set %}` capture rule.)
  def producer_safe?(env : Crinja) : Bool
    !enabled?(env) || env.context.autoescape?
  end

  # A producer's result string wrapped per `producer_safe?`.
  def producer_value(env : Crinja, string : String) : Value
    Value.new(producer_safe?(env) ? SafeString.new(string) : string)
  end

  # markupsafe concatenation of a truncated `prefix` (a slice of `target`,
  # carrying its safety) and an appended `suffix` Value, as `truncate` /
  # `truncate_words` need: the result is safe when escaping is active and
  # either operand is safe, with each operand escaped only if it is plain
  # (so `"abc" + Markup("<i/>")` → `abc<i/>`, `Markup("<b>") + "…"` →
  # `<b>…` with `…` escaped). Otherwise a plain concatenation, byte-identical
  # to the old engine.
  def append_suffix(env : Crinja, prefix : String, target : Value?, suffix : Value) : Value
    prefix_safe = active?(env) && safe?(target)
    return Value.new(prefix + suffix.to_s) unless prefix_safe || (active?(env) && safe?(suffix))
    Value.new(derived((prefix_safe ? prefix : escape(prefix)) + escape(suffix), target, suffix))
  end

  # A filter argument that the filter will INSERT into its text, escaped so
  # it can't smuggle markup into the safe result. A `SafeString` is already
  # trusted; a number or bool keeps its type so `format`/arithmetic still
  # work; anything else (a String, but also a list or map whose stringified
  # form carries author text) is escaped by its string form and marked safe,
  # so the filter's own `to_s` emits the escaped bytes.
  private def escaped_argument(value : Value) : Value
    case value.raw
    when SafeString, Number, Bool, Nil
      value
    else
      Value.new(SafeString.new(escape(value.to_s)))
    end
  end

  # `filter` made to keep a safe target safe (switch on and escaping active):
  # the named arguments it INSERTS into the text (or every positional one)
  # are escaped first — whatever their type — and a String result comes back
  # safe. For a filter that only appends a suffix conditionally (`truncate`,
  # `truncate_words`), the filter escapes its own `end` where it appends it,
  # so those are not wrapped here.
  def keep_safe(filter : Callable::Instance, inserted = [] of String, all_varargs = false) : Callable::Instance
    inner = filter.proc
    names = filter.defaults.keys
    proc = ->(arguments : Arguments) do
      return inner.call(arguments) unless active?(arguments.env) && safe?(arguments.target)
      if all_varargs || !inserted.empty?
        varargs = arguments.varargs.dup
        kwargs = arguments.kwargs.dup
        varargs.map! { |arg| escaped_argument(arg) } if all_varargs
        inserted.each do |name|
          if arg = kwargs[name]?
            kwargs[name] = escaped_argument(arg)
          elsif (index = names.index(name)) && index < varargs.size
            varargs[index] = escaped_argument(varargs[index])
          end
        end
        arguments = Arguments.new(arguments.env, varargs, kwargs, arguments.defaults, arguments.target)
      end
      result = inner.call(arguments)
      raw = result.raw
      raw.is_a?(String) ? Value.new(derived(raw, arguments.target)) : result
    end
    Callable::Instance.new(proc, filter.defaults, filter.name)
  end

  # `format` on a safe format string: escape every argument (`keep_safe` with
  # all_varargs), but `%c` turns a numeric argument into a raw character that
  # bypasses argument escaping (`%c` of 60 → `<`). The argument-level escaping
  # can't reach that generated character, so when the format string contains a
  # `%c` conversion, format the ORIGINAL arguments and return the result
  # PLAIN — the print path then escapes it once (fail-closed; the safe format
  # string's own markup is over-escaped, acceptable for this rare case). `%d`/`%x`/`%.2f`/`%%`… keep
  # the safe path and stay byte-identical.
  #
  # A `%c` conversion as Crystal's sprintf reads it: flags, width, a `1$`
  # position, `*`, a precision, and a named `%<a>` (unreachable — `format`'s
  # varargs are never the hash it needs — but cheap to cover). `%%` is a
  # literal percent and is matched first so `%%c` is not taken for one.
  FORMAT_CONVERSION = /%(?:%|(?:<[^>]*>)?[-+ #0-9.*$]*c)/

  def char_conversion?(format : String) : Bool
    format.scan(FORMAT_CONVERSION).any? { |match| match[0] != "%%" }
  end

  def keep_safe_format(filter : Callable::Instance) : Callable::Instance
    inner = filter.proc
    proc = ->(arguments : Arguments) do
      return inner.call(arguments) unless active?(arguments.env) && safe?(arguments.target)
      # Plain result, ORIGINAL arguments: escaped exactly once where printed.
      return inner.call(arguments) if char_conversion?(arguments.target.to_s)
      varargs = arguments.varargs.map { |arg| escaped_argument(arg) }
      args = Arguments.new(arguments.env, varargs, arguments.kwargs, arguments.defaults, arguments.target)
      result = inner.call(args)
      raw = result.raw
      raw.is_a?(String) ? Value.new(derived(raw, arguments.target)) : result
    end
    Callable::Instance.new(proc, filter.defaults, filter.name)
  end

  # `prepend` / `append` (Crinja's Liquid filters) concatenate like `~`:
  # with escaping active and either side safe, the plain side is escaped
  # and the result is safe. They returned a plain String, so
  # `{{ content | append("…") }}` printed the rendered HTML as text.
  def keep_safe_concat(filter : Callable::Instance, prepend : Bool) : Callable::Instance
    inner = filter.proc
    proc = ->(arguments : Arguments) do
      target = arguments.target || Value.new(nil)
      string = arguments["string"]
      return inner.call(arguments) unless active?(arguments.env) && (safe?(target) || safe?(string))
      Value.new(derived(prepend ? escape(string) + escape(target) : escape(target) + escape(string), target, string))
    end
    Callable::Instance.new(proc, filter.defaults, filter.name)
  end

  # `filter` with a SafeString target handed over as the equal String.
  def string_target(filter : Callable::Instance) : Callable::Instance
    inner = filter.proc
    proc = ->(arguments : Arguments) do
      raw = arguments.target.try(&.raw)
      if raw.is_a?(SafeString)
        arguments = Arguments.new(arguments.env, arguments.varargs, arguments.kwargs, arguments.defaults, Value.new(raw.to_s))
      end
      inner.call(arguments)
    end
    Callable::Instance.new(proc, filter.defaults, filter.name)
  end

  # Filters that keep a safe target safe, with the argument names they insert
  # as text (escaped first). `indent` inserts a string `width`; `replace`/
  # `format` are handled by dedicated filters/wrappers (mixed safety, `%c`).
  KEEP_SAFE = {
    "upper" => [] of String, "lower" => [] of String, "capitalize" => [] of String,
    "center" => [] of String, "indent" => ["width"], "trim" => [] of String,
  }
end

# `xmlattr` builds attributes from an author-controlled mapping and marks
# the result safe, so a key carrying a space (or `/`, `>`, `=`) injects a new
# attribute — `{"x onmouseover": "y"}` becomes ` x onmouseover="y"`. Jinja2
# (CVE-2024-22195, CVE-2024-34064) rejects such keys. Patch the same way, in
# both modes, since the filter marks its output safe regardless of the
# switch. Behaviour change: an invalid key now raises instead of emitting.
module Crinja::Filter
  XMLATTR_INVALID_KEY = /[\s\/>=]/
end

Crinja.filter({autoescape: true}, :xmlattr) do
  # Gate the key validation on the SITE switch, not the context: stage 1's
  # contract is that an OFF build changes no output, and that outranks the
  # hardening. With the switch on, reject an injecting key.
  validate = Crinja::Markup.enabled?(env)
  string = Crinja::SafeString.build do |io|
    target.as_h.each do |key, value|
      next if value.none? || value.undefined?
      key_s = key.to_s
      if validate && (key_s.empty? || key_s.matches?(Crinja::Filter::XMLATTR_INVALID_KEY))
        raise Crinja::RuntimeError.new("xmlattr: invalid attribute name #{key_s.inspect} (no spaces, '/', '>' or '=')")
      end
      io << sprintf %( %s="%s"), HTML.escape(key_s), HTML.escape(value.to_s)
    end
  end
  string = string[1..-1] if string.size > 0 && !arguments["autoescape"].truthy?
  string
end

# `urlize` linked ANY `scheme://` run, so `javascript://x/%0Aalert(1)` became
# a live `javascript:` link (HTML escaping does not neutralise it). Reuse
# hwaro's single unsafe-scheme policy (InlineMarkdown.safe_url?, which refuses
# javascript/vbscript/file and non-image data:) so a refused scheme stays as
# plain (escaped) text, unlinked. Applies in both modes — a pre-existing util
# defect. The rest is the vendored `urlize` body unchanged.
module Crinja::Util
  def self.urlize(text, trim_url_limit, rel, target)
    rel_attr = ""
    rel_attr = %( rel="%s") % HTML.escape(rel.join(' ')) unless rel.empty?

    target_attr = ""
    target_attr = %( target="%s") % HTML.escape(target) unless target.nil? || target.empty?

    SafeString.build do |io|
      text.each_line do |line|
        io << line.gsub(AUTO_LINK_RE) do
          all = $~
          url = all[0]
          next url unless Hwaro::Content::Processors::InlineMarkdown.safe_url?(url)
          display = url
          unless trim_url_limit.nil? || display.size < trim_url_limit
            display = display[0..(trim_url_limit - 3)] + "..."
          end
          %(<a href="#{url}"#{rel_attr}#{target_attr}>#{display}</a>)
        end
      end
    end
  end
end

class Crinja::Config::Autoescape
  # Upstream strips `.jinja` and `.j2` only. Strip whatever wrapper
  # extension hwaro actually loads (`.j2`, `.jinja2`, `.jinja`, `.ecr`) so
  # `page.json.ecr` reads as JSON, not HTML. The strip set is derived from
  # the one list of template extensions (Builder::TEMPLATE_WRAPPER_EXTNAMES)
  # so the two cannot drift.
  def self.match_extension?(extensions : Array(String), filename : String)
    filename = filename.downcase
    extname = File.extname(filename)
    if Hwaro::Core::Build::Builder::TEMPLATE_WRAPPER_EXTNAMES.includes?(extname)
      extname = File.extname(filename[0..(-extname.size - 1)])
    end
    extname.size >= 1 && extensions.includes?(extname[1..-1])
  end
end

class Crinja
  # The one place a value becomes printed text (`{{ x }}`, `join`'s items,
  # `env.evaluate`). Upstream's finalizer escapes a nested string's CONTENTS
  # but writes a container's structural `'`, `[`, `=>` raw, so `{{ page.tags }}`
  # or `{{ [[u]] | join }}` in a single-quoted attribute could break out. With
  # autoescape active, build the WHOLE representation unescaped and escape it
  # once — Jinja2's `escape(str(value))`. A String/SafeString, and every value
  # with the switch off (even inside `{% autoescape true %}`), keeps the
  # upstream bytes.
  def stringify(object, pretty = false)
    if Crinja::Markup.active?(self)
      raw = object.is_a?(Value) ? object.raw : object
      unless raw.is_a?(String) || raw.is_a?(SafeString)
        return Crinja::Markup.escape(Finalizer.stringify(raw, escape: false))
      end
    end
    @finalizer.stringify(object, context.autoescape?)
  end
end

class Crinja
  # Render state that lives exactly as long as the render that set it
  # (Renderer#render restores both in `ensure`), on the environment so a
  # `without context` include, which renders on the long-lived global
  # context, can neither hide it nor leak it:
  #
  #   * `__text_render` — this render's output is text (a template whose name
  #     does not escape, `__no_autoescape`, `render_text`, or an `[outputs]`
  #     JSON/text/CSV render): nothing in it escapes, includes and imports
  #     included, and the Markup rules are off (`Markup.enabled?`).
  #   * `__entry_html` — the caller knows the entry template writes an HTML
  #     or XML file (`Template#render_entry`): it escapes under the switch
  #     whatever its name says. Read once, by the entry render.
  property __text_render : Bool = false
  property __entry_html : Bool = false

  # Run the block with `__text_render` set to `text`, then restore it.
  def with_text_render(text : Bool, &)
    previous = @__text_render
    @__text_render = text
    begin
      yield
    ensure
      @__text_render = previous
    end
  end

  # `{% import %}` / `{% from %}` render in a fresh environment: it carries the
  # text-render state, so a context-free import inside a text output does not
  # escape.
  def __share_features(source : Crinja) : self
    previous_def
    @__text_render = source.__text_render
    self
  end
end

class Crinja::Template
  # Never escape this template's output, nor that of anything it includes.
  # See the file comment.
  property __no_autoescape : Bool = false

  # Render as text: nothing in this render escapes, whatever the template
  # and include names say (a `body_template` produces Markdown).
  def render_text(bindings) : String
    env.with_text_render(true) { render(bindings) }
  end

  # Render as the entry template of an output file whose type hwaro knows:
  # HTML/XML escapes under the switch whatever the template's name says;
  # text never escapes.
  def render_entry(bindings, html : Bool) : String
    return render_text(bindings) unless html
    previous = env.__entry_html
    env.__entry_html = true
    begin
      render(bindings)
    ensure
      env.__entry_html = previous
    end
  end
end

class Crinja::Renderer
  # Upstream body; only the autoescape decision is hwaro's (see the
  # `Crinja#__text_render` note), and it is undone in `ensure` so no render
  # state outlives its render.
  def render(io : IO, template : Template)
    context = env.context
    previous_autoescape = context.autoescape
    previous_text = env.__text_render
    forced_html = env.__entry_html
    env.__entry_html = false
    switch = Crinja::Markup.switch?(env)
    by_name = env.config.autoescape?(template.filename)
    text = previous_text || (switch && !forced_html && (template.__no_autoescape || !by_name))
    env.__text_render = text
    context.autoescape = !text && (forced_html ? switch : by_name)
    begin
      env.context.macros.merge(template.macros)
      output = render(template.nodes)

      @extend_parent_templates.each do |parent_template|
        output = render(parent_template.nodes)

        env.context.extend_path_stack.pop
      end

      resolve_block_stubs(output)

      output.value(io)
    ensure
      context.autoescape = previous_autoescape
      env.__text_render = previous_text
      env.__entry_html = forced_html
    end
  end
end

Crinja.filter(:string) do
  raw = target.raw
  if Crinja::Markup.active?(env)
    raw.is_a?(Crinja::SafeString) ? target : Crinja::Finalizer.stringify(raw)
  else
    env.stringify target
  end
end

# markupsafe's `Markup.replace`: when escaping is active and any operand is
# safe, the SOURCE is escaped (keeping safe source markup), the SEARCH string
# is matched against that escaped source text WITHOUT escaping (`<b>` escaped
# to `&lt;b&gt;` would never match), the REPLACEMENT is escaped unless it is
# safe, the result is safe, and `count` N replaces the first N occurrences in
# the ORIGINAL source (not the already-substituted text; negative/absent =
# all). Otherwise the UNCHANGED crinja_filter_fixes behaviour verbatim, so
# OFF-mode output is byte-identical (its counted-replacement bug and all —
# see DEFERRED in the report).
Crinja.filter({old: Crinja::UNDEFINED, new: Crinja::UNDEFINED, count: nil}, :replace) do
  old_arg = arguments["old"]
  new_arg = arguments["new"]
  count = arguments["count"]
  if Crinja::Markup.active?(env) && (Crinja::Markup.safe?(target) || Crinja::Markup.safe?(old_arg) || Crinja::Markup.safe?(new_arg))
    source = Crinja::Markup.escape(target)
    search = old_arg.to_s
    replacement = Crinja::Markup.escape(new_arg)
    limit = count.raw.nil? ? nil : count.to_i
    Crinja::Value.new(Crinja::Markup.derived(Crinja::Filter.__replace_n(source, search, replacement, limit), target, new_arg))
  else
    search = old_arg.to_s
    if count.raw.nil?
      source = target.raw.is_a?(String | Crinja::SafeString | Crinja::Undefined) ? target.as_s_or_safe : target.to_s
      source.gsub(search, new_arg)
    else
      string = target.to_s
      count.to_i.times do
        running = false
        string = string.sub(search) { running = true; new_arg }
        break unless running
      end
      string
    end
  end
end

module Crinja::Filter
  # Replace up to `limit` occurrences of `search` in `source` (nil/negative =
  # all), counting matches in the ORIGINAL string, not in the partly-replaced
  # result. Mirrors Python `str.replace(old, new, count)`. Byte offsets, not
  # char offsets: on non-ASCII text a char `index`/slice rescans from the
  # start, making the loop quadratic.
  def self.__replace_n(source : String, search : String, replacement : String, limit : Int32?) : String
    return source.gsub(search, replacement) if limit.nil? || limit < 0
    return source if limit == 0 || search.empty?
    bytes = source.to_slice
    String.build(source.bytesize) do |io|
      pos = 0
      done = 0
      while done < limit && (idx = source.byte_index(search, pos))
        io.write bytes[pos, idx - pos]
        io << replacement
        pos = idx + search.bytesize
        done += 1
      end
      io.write bytes[pos, bytes.size - pos]
    end
  end
end

# Same body as crinja_attribute_path_fix.cr's `join`, plus the separator rule
# and the producer-safety rule: it stringifies items without escaping, so with
# the switch on inside a `{% autoescape false %}` block its result is plain
# text (escaped where printed later), not an unconditional SafeString.
Crinja.filter({separator: "", attribute: nil}, :join) do
  separator = arguments["separator"]
  separator = Crinja::Markup.active?(env) ? Crinja::Markup.escape(separator) : separator.to_string
  attribute = arguments["attribute"]

  if target.sequence?
    do_attribute = attribute.truthy?
    attr_name = attribute.to_s
    dotted = attr_name.includes?('.')
    joined = String.build do |io|
      target.join(io, separator) do |item|
        if do_attribute
          item = dotted ? Crinja::Filter.__attr_path(attribute, item) : Crinja::Resolver.resolve_attribute(attr_name, item)
        end
        io << env.stringify(item)
      end
    end
    Crinja::Markup.producer_value(env, joined)
  else
    raise Crinja::TypeError.new("#{target} must be a sequence to join it")
  end
end

Crinja.filter({trim_url_limit: nil, nofollow: false, target: nil, rel: nil}, :urlize) do
  rel = arguments["rel"].to_s.split(' ')

  rel << "nofollow" if arguments["nofollow"].truthy?
  rel |= env.policies.fetch("urlize.rel", "noopener").to_s.split(' ')
  rel = rel.reject(&.empty?).to_set

  # Coerce rather than narrow-cast: Crinja parses an integer literal as Int64
  # (`urlize(trim_url_limit=20)`), which the stock `as(Int32?)` crashed on
  # (same bug on main), and the link `target=` attribute may be a SafeString.
  target_opt = arguments["target"]
  target_attr = (target_opt.none? || target_opt.undefined?) ? env.policies.fetch("urlize.target", nil).as(String?) : target_opt.to_s
  limit_arg = arguments["trim_url_limit"]
  trim_url_limit = (limit_arg.none? || limit_arg.undefined?) ? nil : limit_arg.to_i

  # Escaped first, as Jinja2 does: the links are found in the escaped text,
  # so their href and label are escaped too.
  text = Crinja::Markup.active?(env) ? Crinja::Markup.escape(target) : target.to_s
  Crinja::Markup.producer_value(env, Crinja::Util.urlize(text, trim_url_limit, rel, target_attr).to_s)
end

Crinja::Filter::Library.defaults.map! do |filter|
  next filter unless filter.is_a?(Crinja::Callable::Instance)
  name = filter.name.to_s
  if inserted = Crinja::Markup::KEEP_SAFE[name]?
    Crinja::Markup.keep_safe(filter, inserted)
  elsif name.in?("join", "replace")
    # The `join`/`replace` above replace crinja_filter_fixes' undefined-as-empty ones.
    Crinja::Filter.__undefined_as_empty(filter)
  elsif name == "format"
    Crinja::Markup.keep_safe_format(filter)
  elsif name.in?("prepend", "append")
    Crinja::Markup.keep_safe_concat(filter, name == "prepend")
  elsif name.in?("list", "reverse")
    # They narrow on `String`; a SafeString is listed/reversed as its string
    # (the result is plain, as for a String).
    Crinja::Markup.string_target(filter)
  else
    filter
  end
end

class Crinja::Tag::Filter < Crinja::Tag
  def interpret_output(renderer : Renderer, tag_node : TagNode)
    env = renderer.env
    parser = Parser.new(tag_node.arguments, env.config)
    placeholder, expression = parser.parse_filter_tag

    body = renderer.render(tag_node.block).value
    escaping = Crinja::Markup.active?(env)
    placeholder.value = Value.new(escaping ? SafeString.new(body) : body)

    result = env.evaluate(expression)

    Renderer::RenderedOutput.new(escaping ? Crinja::Markup.escape(result) : result.to_s)
  end
end

class Crinja::Operator::Tilde < Crinja::Operator
  def value(env : Crinja, op1, op2)
    if Crinja::Markup.active?(env) && (Crinja::Markup.safe?(op1) || Crinja::Markup.safe?(op2))
      Crinja::Markup.derived(Crinja::Markup.escape(op1) + Crinja::Markup.escape(op2), op1, op2)
    else
      op1.to_s + op2.to_s
    end
  end
end

# A macro renders its body under the CALLER's context, then marks the result
# safe. When that render happened with escaping active the body is escaped
# markup (safe); when it happened inside `{% autoescape false %}` with the
# switch on the body is raw text, so the result must be plain so printing it
# elsewhere escapes it (`producer_safe?`). Off the switch, always safe
# (byte-identical to the old engine).
#
# A wrapper, not a copy of the upstream body: `previous_def` keeps every
# patch underneath, in particular crinja_recursion_depth_fix.cr's stack
# guard (a copied body dropped it, and unbounded macro recursion killed the
# process again).
class Crinja::Tag::Macro::MacroFunction
  def call(arguments : Arguments)
    result = previous_def
    Crinja::Markup.producer_safe?(arguments.env) ? result : result.to_s
  end
end

# `{{ loop(children) }}` inside a `{% for … recursive %}` — same producer rule.
class Crinja::Tag::For::ForLoop::Recursive
  def call(arguments : Arguments)
    result = previous_def
    Crinja::Markup.producer_safe?(arguments.env) ? result : result.to_s
  end
end

class Crinja::Operator::Plus < Crinja::Operator
  def value(env : Crinja, op1 : Value, op2 : Value)
    if op1.number? && op2.number?
      op1.as_number + op2.as_number
    elsif op1.raw.is_a?(Array)
      adding = op2.raw
      if adding.is_a?(Array)
        op1.as_a + adding
      else
        op1.as_a << Value.new adding
      end
    elsif Crinja::Markup.active?(env) && (Crinja::Markup.safe?(op1) || Crinja::Markup.safe?(op2))
      Crinja::Markup.derived(Crinja::Markup.escape(op1) + Crinja::Markup.escape(op2), op1, op2)
    else
      op1.to_s + op2.to_s
    end
  end
end
