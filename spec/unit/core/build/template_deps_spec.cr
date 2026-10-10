require "../../../spec_helper"
require "../../../../src/core/build/builder"

describe Hwaro::Core::Build::TemplateDeps do
  describe "#closure_hash" do
    # A render hook shapes every page's body, but the caller only folded the
    # hook SOURCES in (RenderHooks registry fingerprint): editing a partial a
    # hook includes left every `--cache` page stale.
    it "changes when a partial included by a render hook changes" do
      templates = {
        "page"               => "{{ content }}",
        "hooks/render-link"  => "<a href=\"{{ url }}\">{{ text }}{% include \"partials/icon.html\" %}</a>",
        "partials/icon"      => "ICON-V1",
        "partials/unrelated" => "X",
      }
      before = Hwaro::Core::Build::TemplateDeps.new(templates).closure_hash("page")

      templates["partials/icon"] = "ICON-V2"
      Hwaro::Core::Build::TemplateDeps.new(templates).closure_hash("page").should_not eq(before)

      templates["partials/unrelated"] = "Y"
      changed = Hwaro::Core::Build::TemplateDeps.new(templates).closure_hash("page")
      templates["partials/unrelated"] = "Z"
      Hwaro::Core::Build::TemplateDeps.new(templates).closure_hash("page").should eq(changed)
    end
  end
end
