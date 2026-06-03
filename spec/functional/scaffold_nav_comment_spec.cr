require "./support/build_helper"
require "../../src/services/scaffolds/blog"
require "../../src/services/scaffolds/simple"

# Regression: the blog and base nav templates ship an HTML comment that
# documents the dynamic `site.sections` loop. The example is wrapped in a
# single `{% raw %}…{% endraw %}` block so Crinja renders it literally
# instead of executing it.
#
# The explanatory prose used to *name* the tag with a bare `{% raw %}`
# ("Wrapped in {% raw %} so this example isn't executed"). Crinja has no
# concept of HTML comments, so it treated that bare tag as a real raw-block
# open: the prose after it was swallowed (rendered as "Wrapped in  so …")
# and the inner `{% raw %}` delimiter leaked verbatim into every generated
# page. These tests build the real scaffolds and assert the hint comment
# renders cleanly.
describe "Scaffold nav hint comment (regression)" do
  it "blog scaffold renders the section-loop hint without leaking raw tags" do
    scaffold = Hwaro::Services::Scaffolds::Blog.new
    build_site(
      scaffold.config_content,
      content_files: scaffold.content_files,
      template_files: scaffold.template_files,
      static_files: scaffold.static_files,
    ) do
      html = File.read("public/index.html")
      # The example loop is shown literally inside the comment…
      html.should contain("{% for s in site.sections")
      # …but the raw-block delimiters themselves are consumed, never leaked.
      html.should_not contain("{% raw %}")
      html.should_not contain("{% endraw %}")
      # …and the explanatory prose survives intact.
      html.should contain("wrapped in a raw block")
    end
  end

  it "simple scaffold (base nav) renders the section-loop hint without leaking raw tags" do
    scaffold = Hwaro::Services::Scaffolds::Simple.new
    build_site(
      scaffold.config_content,
      content_files: scaffold.content_files,
      template_files: scaffold.template_files,
      static_files: scaffold.static_files,
    ) do
      html = File.read("public/index.html")
      html.should contain("{% for s in site.sections")
      html.should_not contain("{% raw %}")
      html.should_not contain("{% endraw %}")
      html.should contain("wrapped in a raw block")
    end
  end
end
