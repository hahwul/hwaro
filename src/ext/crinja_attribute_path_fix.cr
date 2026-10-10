# Dotted attribute paths in `map`, `selectattr`, `rejectattr`, `sort` and
# `join`, as in Jinja2 (`attribute="extra.featured"`, `"tags.0"`).
#
# Upstream looked the whole string up as ONE key, so
# `pages | selectattr("extra.featured")` silently selected nothing,
# `rejectattr` kept everything, `map(attribute="author.name")` produced
# empties and `sort(attribute="extra.weight")` raised. A name without a dot
# resolves exactly as before. Also from Jinja2: `map(…, default=…)`, a
# comma-separated `sort(attribute="year,title")`, and `sort(reverse=true)`
# keeping equal items in their original order.
module Crinja::Filter
  def self.__attr_path(path : Value, item : Value) : Value
    name = path.raw
    return Resolver.resolve_getattr(path, item) unless name.is_a?(String) && name.includes?('.')

    name.split('.').reduce(item) do |value, part|
      break value if value.undefined?
      resolved = Resolver.resolve_getattr(part, value)
      if resolved.undefined? && value.indexable? && part.each_char.all?(&.ascii_number?) && (index = part.to_i?)
        value[index]?.try { |found| resolved = found }
      end
      resolved
    end
  end

  # The `sort` / `dictsort` key comparison: strings case-insensitively unless
  # asked otherwise, anything else by `<=>`.
  def self.__compare(a : Value, b : Value, case_sensitive : Bool) : Int32
    return a.as_s.compare(b.as_s, true) if !case_sensitive && a.string? && b.string?
    (a <=> b) || raise ArgumentError.new("Comparison of #{a} and #{b} failed")
  end

  def self.__sort(array : Array(Value), paths : Array(Value)?, case_sensitive : Bool, direction : Int32) : Array(Value)
    # Upstream resolved keys only while comparing, so a single item never
    # touched its attribute (and never raised on it).
    return array if array.size < 2

    keyed = array.map do |item|
      key = if paths
              paths.map { |path| path.as_s.includes?('.') ? __attr_path(path, item) : item[path.as_s] }
            else
              [item]
            end
      {key, item}
    end

    keyed.sort do |(a_key, _), (b_key, _)|
      order = 0
      a_key.each_with_index do |a, i|
        order = __compare(a, b_key[i], case_sensitive)
        break unless order == 0
      end
      order * direction
    end.map(&.[1])
  end

  # Upstream `select_reject_attr`, resolving the attribute through
  # `__attr_path`.
  macro __select_reject_attr_path(func)
    varargs = arguments.varargs

    attribute = varargs.shift

    if varargs.size == 0
      target.{{ func.id }} do |item|
        Crinja::Filter.__attr_path(attribute, item).truthy?
      end
    else
      test = env.tests[varargs.shift.as_s]

      target.{{ func.id }} do |item|
        args = Arguments.new(env, varargs, arguments.kwargs, target: Crinja::Filter.__attr_path(attribute, item))
        env.execute_call(test, args).truthy?
      end
    end
  end

  Crinja.filter(:selectattr) do
    Crinja::Filter.__select_reject_attr_path(:select)
  end

  Crinja.filter(:rejectattr) do
    Crinja::Filter.__select_reject_attr_path(:reject)
  end

  Crinja.filter(:map) do
    if target.none?
      ""
    elsif arguments.is_set?("attribute")
      attribute = arguments["attribute"]
      default = arguments.kwargs["default"]?
      target.map do |item|
        value = Crinja::Filter.__attr_path(attribute, item)
        default && value.undefined? ? default : value
      end
    else
      varargs = arguments.varargs
      filter = env.filters[varargs.shift.as_s]

      target.map do |item|
        args = Arguments.new(env, varargs, arguments.kwargs, target: item)
        arguments.env.execute_call(filter, args)
      end
    end
  end

  Crinja.filter({
    reverse:        false,
    case_sensitive: false,
    attribute:      nil,
  }, :sort) do
    case_sensitive = arguments["case_sensitive"].truthy?
    direction = arguments["reverse"].truthy? ? -1 : 1
    attribute = arguments["attribute"]
    paths = attribute.string? ? attribute.as_s.split(',').map { |part| Value.new(part) } : nil

    Crinja::Filter.__sort(target.to_a, paths, case_sensitive, direction)
  end

  Crinja.filter({separator: "", attribute: nil}, :join) do
    separator = arguments["separator"].to_string
    attribute = arguments["attribute"]

    if target.sequence?
      do_attribute = attribute.truthy?
      attr_name = attribute.to_s
      dotted = attr_name.includes?('.')
      SafeString.build do |io|
        target.join(io, separator) do |item|
          if do_attribute
            item = dotted ? Crinja::Filter.__attr_path(attribute, item) : Resolver.resolve_attribute(attr_name, item)
          end
          io << env.stringify(item)
        end
      end
    else
      raise TypeError.new("#{target} must be a sequence to join it")
    end
  end
end
