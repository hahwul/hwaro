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

  # Whether `[templates] autoescape` is on for this environment (the site
  # switch), independent of a `{% autoescape %}` tag. `configure_autoescape`
  # sets `default_for_string` to the switch, so an OFF-mode build never takes
  # the Markup code paths even inside a `{% autoescape true %}` block — its
  # output stays byte-identical to the pre-autoescape engine.
  def enabled?(env : Crinja) : Bool
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
    Value.new(SafeString.new((prefix_safe ? prefix : escape(prefix)) + escape(suffix)))
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
      raw.is_a?(String) ? Value.new(SafeString.new(raw)) : result
    end
    Callable::Instance.new(proc, filter.defaults, filter.name)
  end

  # `format` on a safe format string: escape every argument (`keep_safe` with
  # all_varargs), but `%c` turns a numeric argument into a raw character that
  # bypasses argument escaping (`%c` of 60 → `<`). The argument-level escaping
  # can't reach that generated character, so when the format string contains a
  # `%c` conversion, return the whole result PLAIN — the print path then
  # escapes it once (fail-closed; the safe format string's own markup is
  # over-escaped, acceptable for this rare case). `%d`/`%x`/`%.2f`/`%%`… keep
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
      varargs = arguments.varargs.map { |arg| escaped_argument(arg) }
      args = Arguments.new(arguments.env, varargs, arguments.kwargs, arguments.defaults, arguments.target)
      result = inner.call(args)
      raw = result.raw
      return result unless raw.is_a?(String)
      char_conversion?(arguments.target.to_s) ? Value.new(raw) : Value.new(SafeString.new(raw))
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

class Crinja::Template
  # Never escape this template's own output (its includes still follow
  # their own names). See the file comment.
  property __no_autoescape : Bool = false
end

class Crinja::Renderer
  # Upstream body; only the autoescape decision consults `__no_autoescape`.
  def render(io : IO, template : Template)
    env.context.autoescape = !template.__no_autoescape && env.config.autoescape?(template.filename)

    env.context.macros.merge(template.macros)
    output = render(template.nodes)

    @extend_parent_templates.each do |parent_template|
      output = render(parent_template.nodes)

      env.context.extend_path_stack.pop
    end

    resolve_block_stubs(output)

    output.value(io)
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
    Crinja::Value.new(Crinja::SafeString.new(Crinja::Filter.__replace_n(source, search, replacement, limit)))
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
  # result. Mirrors Python `str.replace(old, new, count)`.
  def self.__replace_n(source : String, search : String, replacement : String, limit : Int32?) : String
    return source.gsub(search, replacement) if limit.nil? || limit < 0
    return source if limit == 0 || search.empty?
    String.build do |io|
      pos = 0
      done = 0
      while done < limit && (idx = source.index(search, pos))
        io << source[pos, idx - pos] << replacement
        pos = idx + search.size
        done += 1
      end
      io << source[pos..]
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
      SafeString.new(Crinja::Markup.escape(op1) + Crinja::Markup.escape(op2))
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
class Crinja::Tag::Macro::MacroFunction
  def call(arguments : Arguments)
    arguments.defaults = @defaults

    arguments.env.with_scope(arguments.to_h) do |context|
      context.merge!({
        "varargs" => arguments.varargs,
        "kwargs"  => arguments.kwargs,
      })

      body = String.build do |io|
        Crinja::Renderer.new(@renderer.template, arguments.env).render(children).value(io)
      end
      Crinja::Markup.producer_safe?(arguments.env) ? SafeString.new(body) : body
    end
  end
end

# `{{ loop(children) }}` inside a `{% for … recursive %}` — same producer rule.
class Crinja::Tag::For::ForLoop::Recursive
  def call(arguments : Arguments)
    sub_iterator = arguments.varargs.first

    sub_loop = self.class.new(@loop_runner, sub_iterator)
    sub_loop.depth0 = depth

    body = String.build do |io|
      io << @loop_runner.run_loop(sub_loop).value
    end
    Crinja::Markup.producer_safe?(arguments.env) ? SafeString.new(body) : body
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
      SafeString.new(Crinja::Markup.escape(op1) + Crinja::Markup.escape(op2))
    else
      op1.to_s + op2.to_s
    end
  end
end
