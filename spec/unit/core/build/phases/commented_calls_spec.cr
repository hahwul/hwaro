require "../../../../spec_helper"
require "../../../../support/build_helper"

# A shortcode or include_md call inside an HTML comment is commented out:
# it stays literal, and the comment stays one comment. Expanding it put a
# `-->` (the shortcode placeholder's, or an included file's own
# `<!-- #region -->`) inside the author's comment, which ended it early:
# the rest showed as page text and the closing `-->` as `--&gt;`, which no
# browser reads as a closer, so the comment hid the rest of the page.
describe "Commented-out shortcode and include calls" do
  it "keep the author's comment intact" do
    page = <<-MD
      +++
      title = "P"
      +++
      Before

      <!--
      {{ youtube(id="abc") }}
      {{ include_md(path="static/part.md") }}
      TODO
      -->

      After
      MD
    build_site(
      %(title = "T"\nbase_url = "http://localhost"\n),
      content_files: {"p.md" => page},
      static_files: {"part.md" => "## Part\n\n<!-- #region a -->\nregion\n<!-- #endregion a -->\n"},
      template_files: {"page.html" => "<main>{{ content | safe }}</main>"},
    ) do |dir|
      html = File.read(File.join(dir, "public", "p", "index.html"))
      html.should contain(%(<!--\n{{ youtube(id="abc") }}\n{{ include_md(path="static/part.md") }}\nTODO\n-->))
      html.should contain("<p>After</p>")
      html.should_not contain("--&gt;")
      html.should_not contain("sc-video")
    end
  end
end
