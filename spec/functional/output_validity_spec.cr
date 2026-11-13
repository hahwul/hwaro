require "../support/build_helper"
require "../../src/services/scaffolds/blog"

# Generated HTML must satisfy the HTML standard's own requirements, e.g. a
# `<time datetime>` holds a valid date string and a link has a name.
describe "Generated HTML validity" do
  it "blog scaffold: an undated post renders no empty <time datetime>, and a title-less page is a named link in its tag listing" do
    scaffold = Hwaro::Services::Scaffolds::Blog.new
    content = scaffold.content_files.merge({
      "posts/undated.md" => "+++\ntitle = \"Undated\"\n+++\n\nbody\n",
      "untitled.md"      => "+++\ntitle = \"\"\ntags = [\"misc\"]\n+++\n\nbody\n",
    })
    build_site(
      scaffold.minimal_config_content,
      content_files: content,
      template_files: scaffold.template_files,
      static_files: scaffold.static_files,
    ) do
      File.read("public/posts/undated/index.html").should_not contain(%(datetime=""))
      File.read("public/tags/misc/index.html").should contain(%(/untitled/">My Blog</a></li>))
    end
  end
end
