# Monkey-patch for Markd's inline-HTML renderer, mirroring
# ext/markd_unsafe_image_fix.cr.
#
# Inside an image description Markd writes the alt attribute's value from
# the description, escaping its text, but upstream `HTMLRenderer#html_inline`
# still emits a raw HTML node there verbatim. A `"` in the node ends the
# attribute: `![a <span class="x">b</span>](i.png)` rendered
# `alt="a <span class="` followed by stray attributes and text. Hwaro's
# shortcode placeholder is such a node, so `![alt {{ sc() }}](i.png)` broke
# the `<img>` the same way once the placeholder became the shortcode's HTML.
# Escape the node inside an image description: the attribute keeps the same
# value (a literal `<b>` and `&lt;b&gt;` read the same in an attribute), now
# with its quotes and ampersands escaped.

require "markd"

{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_image_alt_html_fix.cr replaces Markd::HTMLRenderer#html_inline from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Markd
  class HTMLRenderer
    def html_inline(node : Node, entering : Bool)
      inline_html(@options.safe? ? "<!-- raw HTML omitted -->" : node.text)
    end

    # Raw inline HTML as written, or escaped when it sits in an image's alt
    # attribute (`@disable_tag` is raised for the image description).
    private def inline_html(content : String)
      @disable_tag > 0 ? output(content) : literal(content)
    end
  end
end
