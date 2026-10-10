# Monkey-patch for Markd's image renderer — kept here so we don't fork the
# vendored library, mirroring ext/markd_uri_fix.cr.
#
# Under `safe`, upstream `Markd::HTMLRenderer#image` blanks an unsafe
# destination as `<img src="" alt=""`, closing the alt attribute before the
# alt text is written. The (escaped) alt text then lands outside any quotes,
# so `![x onerror=alert(1)//](javascript:x)` rendered a live `onerror`
# handler. Emit the one opening quote the safe branch was missing.

require "markd"

{% if Markd::VERSION != "0.5.0" %}
  {% raise "src/ext/markd_unsafe_image_fix.cr replaces Markd::HTMLRenderer#image from markd 0.5.0, but markd #{Markd::VERSION} is vendored. Re-check the patch against the new upstream source and update the version pin." %}
{% end %}

module Markd
  class HTMLRenderer
    def image(node : Node, entering : Bool)
      if entering
        if @disable_tag == 0
          destination = node.data["destination"].as(String)
          if @options.safe? && potentially_unsafe(destination)
            literal(%(<img src="" alt="))
          else
            destination = resolve_uri(destination, node)
            literal(%(<img src="#{escape(destination)}" alt="))
          end
        end
        @disable_tag += 1
      else
        @disable_tag -= 1
        if @disable_tag == 0
          if (title = node.data["title"].as(String)) && !title.empty?
            literal(%(" title="#{escape(title)}))
          end
          literal(%(" />))
        end
      end
    end
  end
end
