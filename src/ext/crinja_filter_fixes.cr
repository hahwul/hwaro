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

  target.to_a.sort do |a, b|
    x, y = a[index], b[index]
    order = if !case_sensitive && x.string? && y.string?
              x.as_s.compare(y.as_s, true)
            else
              (x <=> y) || raise ArgumentError.new("Comparison of #{x} and #{y} failed")
            end
    order * direction
  end
end
