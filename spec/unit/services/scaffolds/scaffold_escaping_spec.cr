require "../../../spec_helper"
require "../../../support/build_helper"
require "../../../../src/services/scaffolds/registry"

# Scaffold templates keep `| e` on every value that comes from content, so a
# site that sets `[templates] autoescape = false` stays protected, and under
# the default the output is the same (`| e` never escapes twice).
# `page.section` is a content directory NAME, and the headers printed it raw
# into `data-section="…"`.
describe "scaffold template escaping" do
  {
    "simple" => Hwaro::Services::Scaffolds::Simple.new,
    "blog"   => Hwaro::Services::Scaffolds::Blog.new,
    "docs"   => Hwaro::Services::Scaffolds::Docs.new,
    "book"   => Hwaro::Services::Scaffolds::Book.new,
  }.each do |name, scaffold|
    it "#{name}: a quote in a section directory name stays inside data-section, autoescape on or off" do
      posix_only!(%(a directory name containing '"'))
      [BASIC_CONFIG, BASIC_CONFIG + "\n[templates]\nautoescape = false\n"].each do |config|
        build_site(
          config,
          content_files: {"x\" onmouseover=\"y/a.md" => "+++\ntitle = \"a\"\n+++\nbody\n"},
          template_files: scaffold.template_files,
        ) do |dir|
          html = File.read(File.join(dir, "public", %(x" onmouseover="y), "a", "index.html"))
          html.should contain(%(<body data-section="x&quot; onmouseover=&quot;y">))
        end
      end
    end
  end
end
