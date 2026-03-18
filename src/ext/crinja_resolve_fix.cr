# Monkey-patch Crinja's variable resolution order.
#
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
