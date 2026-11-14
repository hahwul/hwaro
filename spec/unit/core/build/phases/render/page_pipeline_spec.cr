require "../../../../../spec_helper"
require "../../../../../support/build_helper"

# Under a `…/docs` base_url, a `content/docs/` section makes a content link
# that starts with `/docs/` ambiguous: hand-prefixed (`/docs/about/` for the
# root page `/about/`) or site-relative (`/docs/only/` for the section page,
# served at `/docs/docs/only/`). It is prefixed only when the site-relative
# reading is the one that names a route.
private BASE_PATH_COLLISION_CONTENT = {
  "_index.md" => "+++\ntitle = \"Home\"\n+++\n" \
                 "[only](/docs/only/) [amb](/docs/intro/) [hand](/docs/about/) [none](/docs/missing/) " \
                 "[at-root](@/intro.md) [at-sec](@/docs/only.md)\n\n" \
                 "<a href=\"/docs/only/#x\">raw</a> <img src=\"/img/a.png\" srcset=\"/docs/file.pdf 1x, /docs/img/a.png 2x\">\n",
  "about.md"       => "+++\ntitle = \"About\"\n+++\na",
  "intro.md"       => "+++\ntitle = \"Root intro\"\n+++\nr",
  "docs/_index.md" => "+++\ntitle = \"Docs\"\n+++\n",
  "docs/intro.md"  => "+++\ntitle = \"Intro\"\n+++\ni",
  "docs/only.md"   => "+++\ntitle = \"Only\"\n+++\no",
}

private BASE_PATH_COLLISION_TEMPLATES = {"page.html" => "{{ content }}", "section.html" => "{{ content }}", "index.html" => "{{ content }}"}

describe "content links under a base path a section shares" do
  it "prefixes a link only its site-relative reading resolves, and nothing else" do
    build_site(
      %(title = "T"\nbase_url = "https://example.com/docs"\n),
      content_files: BASE_PATH_COLLISION_CONTENT,
      template_files: BASE_PATH_COLLISION_TEMPLATES,
      static_files: {"docs/file.pdf" => "pdf", "img/a.png" => "png"},
    ) do |dir|
      html = File.read(File.join(dir, "public", "index.html"))
      html.should contain(%(<a href="/docs/docs/only/">only</a>))
      html.should contain(%(<a href="/docs/docs/only/#x">raw</a>))
      html.should contain(%(srcset="/docs/docs/file.pdf 1x, /docs/img/a.png 2x"))
      html.should contain(%(src="/docs/img/a.png"))
      # Both readings resolve, only the prefixed one does, or neither: as written.
      html.should contain(%(<a href="/docs/intro/">amb</a>))
      html.should contain(%(<a href="/docs/about/">hand</a>))
      html.should contain(%(<a href="/docs/missing/">none</a>))
      # `@/` links carry the prefix exactly once.
      html.should contain(%(<a href="/docs/intro/">at-root</a>))
      html.should contain(%(<a href="/docs/docs/only/">at-sec</a>))
    end
  end

  it "counts the home and taxonomy pages as routes of the unprefixed reading" do
    build_site(
      %(title = "T"\nbase_url = "https://example.com/docs"\n\n[[taxonomies]]\nname = "tags"\n),
      content_files: {
        "about.md"       => "+++\ntitle = \"About\"\ntags = [\"x\"]\n+++\n[home](/docs/) [tags](/docs/tags/) [term](/docs/tags/x/) [only](/docs/only/)",
        "docs/_index.md" => "+++\ntitle = \"Docs\"\n+++\n",
        "docs/only.md"   => "+++\ntitle = \"Only\"\n+++\no",
        "docs/tags.md"   => "+++\ntitle = \"Tags guide\"\n+++\nt",
        "docs/tags/x.md" => "+++\ntitle = \"X guide\"\n+++\nx",
      },
      template_files: BASE_PATH_COLLISION_TEMPLATES,
    ) do |dir|
      html = File.read(File.join(dir, "public", "about", "index.html"))
      html.should contain(%(<a href="/docs/">home</a> <a href="/docs/tags/">tags</a> <a href="/docs/tags/x/">term</a> <a href="/docs/docs/only/">only</a>))
    end
  end
end
