require "../../../../spec_helper"
require "../../../../support/build_helper"

# Under `[markdown] safe = true` the transclusion wrapper was unmarked raw
# HTML: safe mode dropped its opening `<div>` but kept the `</div>`, which
# balanced (and closed) the enclosing container's div instead.
describe "Note transclusion under safe mode" do
  it "keeps the wrapper, so an enclosing container stays well-nested" do
    build_site(
      %(title = "T"\nbase_url = "http://localhost"\n\n[markdown]\nsafe = true\nwikilinks = true\ncontainers = true\n),
      content_files: {
        "note.md" => "+++\ntitle = \"Note\"\n+++\nNote body.\n",
        "p.md"    => "+++\ntitle = \"P\"\n+++\n:::tip\n![[note]]\n\nInside <b>raw</b>.\n:::\n\nAfter\n",
      },
      template_files: {"page.html" => "<main>{{ content | safe }}</main>"},
    ) do
      html = File.read("public/p/index.html")
      html.should contain(<<-HTML)
        <div class="admonition admonition-tip">
        <p class="admonition-title">Tip</p>
        <div class="transclusion" data-source="/note/">
        <p>Note body.</p>
        </div>
        <p>Inside <!-- raw HTML omitted -->raw<!-- raw HTML omitted -->.</p>
        </div>
        <p>After</p>
        HTML
    end
  end
end
