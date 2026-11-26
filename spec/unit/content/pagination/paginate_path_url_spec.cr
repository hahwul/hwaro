require "../../../spec_helper"
require "../../../support/build_helper"

# `paginate_path` lands in every pager URL. A `#` or `?` in it ended the URL
# path there (`/blog/p#x/2/` is `/blog/p` plus a fragment), so every link to
# pager 2+ pointed at a page that does not exist, while the pages themselves
# were written under `p#x/`. Pager URLs now escape it the way `page.url` does.
describe "paginate_path in pager URLs" do
  it "escapes # and ? in pager URLs and keeps the raw output directory" do
    content = {"blog/_index.md" => "+++\ntitle = \"Blog\"\npaginate = 1\npaginate_path = \"p#x?y\"\n+++\n"}
    (1..3).each { |i| content["blog/p#{i}.md"] = "+++\ntitle = \"P#{i}\"\ndate = 2024-01-0#{i}\n+++\nbody" }
    templates = {
      "page.html"    => "{{ content }}",
      "section.html" => "url={{ page.url }} next={{ paginator.next }} last={{ paginator.last }} base={{ paginator.base_url }}|{{ pagination_seo_links }}",
    }
    build_site(BASIC_CONFIG, content_files: content, template_files: templates) do |dir|
      first = File.read(File.join(dir, "public/blog/index.html"))
      first.should contain("next=/blog/p%23x%3Fy/2/ last=/blog/p%23x%3Fy/3/ base=/blog/p%23x%3Fy/")
      first.should contain(%(rel="next" href="http://localhost/blog/p%23x%3Fy/2/"))
      second = File.read(File.join(dir, "public/blog/p#x?y/2/index.html"))
      second.should contain("url=/blog/p%23x%3Fy/2/ next=/blog/p%23x%3Fy/3/")
      File.exists?(File.join(dir, "public/blog/p#x?y/3/index.html")).should be_true
    end
  end
end
