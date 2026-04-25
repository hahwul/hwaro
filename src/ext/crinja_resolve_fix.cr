# Monkey-patches for Crinja's runtime — kept here so we don't fork the
# vendored library. Each patch carries an issue link so we can remove it
# once Crinja ships an equivalent fix upstream.

# === 1. Resolution-order fix ============================================
# Upstream Crinja resolves global functions *before* context variables,
# which means a loop variable whose name collides with a registered
# function (e.g. `asset`) is shadowed by the function instead of the
# other way around.
#
# This patch flips the priority: context (scope) variables are checked
# first, and only when the name is undefined in every scope do we fall
# back to the global function registry.
#
# See: https://github.com/hahwul/hwaro/issues/224
# TODO: Remove this file when Crinja releases a version that includes
#       https://github.com/straight-shoota/crinja/pull/102
class Crinja
  def resolve(name : String) : Value
    value = context[name]
    if !value.undefined?
      value
    elsif functions.has_key?(name)
      Value.new functions[name]
    else
      value # return the original Undefined
    end
  end
end

# === 2. Safer attribute resolution on indexable values ==================
# Upstream `Resolver.resolve_attribute` calls `name.to_i` (which raises
# `ArgumentError("Invalid Int32: \"<name>\"")` on non-numeric names) for
# any indexable value, including Strings. The most common way to hit
# this is iterating a hash with a single loop variable —
#
#   {% for k in site.taxonomies.tags %}{{ k.name }}{% endfor %}
#
# yields hash keys (Strings), and `k.name` then runs `"<key>".to_i`.
# The user sees a Crystal-internal stack trace with no template
# file:line:col, which makes the typo (`for k, v in …`) impossible to
# locate.
#
# Two changes here:
#
# 1. Use `to_i?` so non-numeric attribute names cleanly fall through
#    instead of crashing the resolver.
# 2. When attribute access is non-numeric *and* the underlying value is
#    a String, raise `UndefinedError`. Crinja's `MemberExpression`
#    evaluator catches and re-raises it labeled with the full
#    expression (`k.name`), which our `Error [HWARO_E_TEMPLATE]`
#    formatter prints with template file:line:col. Default `Undefined`
#    renders as empty, which is the correct behavior for hashes /
#    objects (`{% if page.optional %}`-style guards rely on it), but
#    on a primitive String the access is almost always a typo, so a
#    loud error is more helpful than silent empty output.
#
# See: https://github.com/hahwul/hwaro/issues/482
# === 3. Empty-collection falsiness (Jinja2 alignment) ==================
# Upstream `Value#truthy?` only treats `false`, `0`, `nil`, and
# `Undefined` as falsy. Python Jinja2 also treats empty collections —
# `[]`, `{}`, `""` — as falsy, which is what `{% if items %}` and
# `{% if page.translations %}` rely on across hwaro's docs and
# scaffolds. Without this patch, the canonical lang-switcher idiom
#
#   {% if page.translations %}<nav>…</nav>{% endif %}
#
# always rendered an empty `<nav>` for pages with no translations,
# because Crinja saw `[]` as truthy.
#
# See: https://github.com/hahwul/hwaro/issues/486
struct Crinja::Value
  def truthy?
    raw = @raw
    return false if raw == false
    return false if raw.is_a?(Number) && raw == 0
    return false if raw.nil?
    return false if undefined?
    return false if raw.is_a?(String) && raw.empty?
    return false if raw.is_a?(Crinja::SafeString) && raw.to_s.empty?
    return false if raw.is_a?(Indexable) && raw.empty?
    return false if raw.is_a?(Hash) && raw.empty?
    return false if raw.is_a?(Crinja::Tuple) && raw.empty?
    true
  end
end

module Crinja::Resolver
  def self.resolve_attribute(name, object : Crinja::Value) : Crinja::Value
    raise Crinja::UndefinedError.new(name.to_s) if object.undefined?

    value = resolve_getattr(name, object)

    if value.undefined?
      if object.indexable? && (idx = name.to_s.to_i?)
        if v = object[idx]?
          return Crinja::Value.new v
        end
      end

      # Strings, SafeStrings, and Tuples don't have hash-style attribute
      # access — `.attr` on these is almost always a typo. The most
      # common case is iterating a hash with a single loop variable,
      # which yields `Tuple(key, value)` per iteration:
      #
      #   {% for tag in site.taxonomies.tags %}{{ tag.name }}{% endfor %}
      #                                            ^~~~~~~~~ — `tag` is a Tuple
      #
      # Raise so the evaluator can label the expression and the
      # template error formatter shows file:line:col.
      raw = object.raw
      if raw.is_a?(String) || raw.is_a?(Crinja::SafeString) || raw.is_a?(Crinja::Tuple)
        raise Crinja::UndefinedError.new(name.to_s)
      end
    end

    value
  end
end
