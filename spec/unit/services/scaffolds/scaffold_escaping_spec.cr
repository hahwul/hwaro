require "../../../spec_helper"
require "../../../support/build_helper"
require "../../../../src/services/scaffolds/registry"

# Scaffold templates run with autoescape off, so every value that comes from
# content must be escaped where it is printed. `page.section` is a content
# directory NAME, and the headers printed it raw into `data-section="…"`.
describe "scaffold template escaping" do
  {
    "simple" => Hwaro::Services::Scaffolds::Simple.new,
    "blog"   => Hwaro::Services::Scaffolds::Blog.new,
    "docs"   => Hwaro::Services::Scaffolds::Docs.new,
    "book"   => Hwaro::Services::Scaffolds::Book.new,
  }.each do |name, scaffold|
    it "#{name}: a quote in a section directory name stays inside data-section" do
      posix_only!(%(a directory name containing '"'))
      build_site(
        BASIC_CONFIG,
        content_files: {"x\" onmouseover=\"y/a.md" => "+++\ntitle = \"a\"\n+++\nbody\n"},
        template_files: scaffold.template_files,
      ) do |dir|
        html = File.read(File.join(dir, "public", %(x" onmouseover="y), "a", "index.html"))
        html.should contain(%(<body data-section="x&quot; onmouseover=&quot;y">))
      end
    end
  end
end
