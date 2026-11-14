# A list or mapping turned into text reads the way `{{ value }}` prints
# it, as Jinja2's `str()` does.
#
# Upstream `Value#to_s` handed collections to Crystal's own `to_s`, which
# prints each element's debug form, so `{{ 'tags: ' ~ page.tags }}`,
# `{{ '%s' | format(items) }}` or `{{ items | upper }}` rendered
# `[Crinja::Value<"a">, …]` (and `{Crinja::Value<"k"> => …}` for a map).
struct Crinja::Value
  def to_s(io)
    case raw = @raw
    when Array, Hash, Crinja::Tuple
      Crinja::Finalizer.stringify(io, raw)
    else
      raw.to_s(io)
    end
  end
end
