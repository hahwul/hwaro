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

  # Filters that keep a safe target safe, with the argument names they insert
  # as text (escaped first). `indent` inserts a string `width`; `replace` is
  # handled by a dedicated filter below (mixed safe/unsafe operands).
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
  string = Crinja::SafeString.build do |io|
    target.as_h.each do |key, value|
      next if value.none? || value.undefined?
      key_s = key.to_s
      if key_s.empty? || key_s.matches?(Crinja::Filter::XMLATTR_INVALID_KEY)
        raise Crinja::RuntimeError.new("xmlattr: invalid attribute name #{key_s.inspect} (no spaces, '/', '>' or '=')")
      end
      io << sprintf %( %s="%s"), HTML.escape(key_s), HTML.escape(value.to_s)
    end
  end
  string = string[1..-1] if string.size > 0 && !arguments["autoescape"].truthy?
  string
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
# safe, escape the unsafe operands (the source too when a safe replacement is
# present), keep the safe ones, and return a safe result. Otherwise the
# unchanged crinja_filter_fixes behaviour, so OFF-mode output is identical.
Crinja.filter({old: Crinja::UNDEFINED, new: Crinja::UNDEFINED, count: nil}, :replace) do
  old_arg = arguments["old"]
  new_arg = arguments["new"]
  count = arguments["count"]
  if Crinja::Markup.active?(env) && (Crinja::Markup.safe?(target) || Crinja::Markup.safe?(old_arg) || Crinja::Markup.safe?(new_arg))
    source = Crinja::Markup.escape(target)
    search = Crinja::Markup.escape(old_arg)
    replacement = Crinja::Markup.escape(new_arg)
    result = if count.raw.nil?
               source.gsub(search, replacement)
             else
               string = source
               count.to_i.times do
                 running = false
                 string = string.sub(search) { running = true; replacement }
                 break unless running
               end
               string
             end
    Crinja::Value.new(Crinja::SafeString.new(result))
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

# Same body as crinja_attribute_path_fix.cr's `join`, plus the separator rule.
Crinja.filter({separator: "", attribute: nil}, :join) do
  separator = arguments["separator"]
  separator = Crinja::Markup.active?(env) ? Crinja::Markup.escape(separator) : separator.to_string
  attribute = arguments["attribute"]

  if target.sequence?
    do_attribute = attribute.truthy?
    attr_name = attribute.to_s
    dotted = attr_name.includes?('.')
    Crinja::SafeString.build do |io|
      target.join(io, separator) do |item|
        if do_attribute
          item = dotted ? Crinja::Filter.__attr_path(attribute, item) : Crinja::Resolver.resolve_attribute(attr_name, item)
        end
        io << env.stringify(item)
      end
    end
  else
    raise Crinja::TypeError.new("#{target} must be a sequence to join it")
  end
end

Crinja.filter({trim_url_limit: nil, nofollow: false, target: nil, rel: nil}, :urlize) do
  rel = arguments["rel"].to_s.split(' ')

  rel << "nofollow" if arguments["nofollow"].truthy?
  rel |= env.policies.fetch("urlize.rel", "noopener").to_s.split(' ')
  rel = rel.reject(&.empty?).to_set

  target_attr = arguments.fetch("target") { env.policies.fetch("urlize.target", nil) }.raw.as(String?)
  trim_url_limit = arguments["trim_url_limit"].raw.as(Int32?)

  # Escaped first, as Jinja2 does: the links are found in the escaped text,
  # so their href and label are escaped too.
  text = Crinja::Markup.active?(env) ? Crinja::Markup.escape(target) : target.to_s
  Crinja::Util.urlize(text, trim_url_limit, rel, target_attr)
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
    Crinja::Markup.keep_safe(filter, all_varargs: true)
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
