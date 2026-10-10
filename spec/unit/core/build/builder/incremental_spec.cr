require "../../../../spec_helper"
require "../../../../../src/core/build/builder"

describe "Builder#run_incremental output collisions" do
  it "republishes a bundle's assets once the collision that suppressed it is gone" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts/a")
        FileUtils.mkdir_p("content/posts/x")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("content/posts/a/index.md", "+++\ntitle = \"A\"\n+++\n")
        File.write("content/posts/a/cover.png", "A-cover")
        File.write("content/posts/x/index.md", "+++\ntitle = \"X\"\n+++\n")
        File.write("content/posts/x/cover.png", "X-cover")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/a/index.md"], options)

        # posts/a takes /posts/x/ (it sorts first): the URL serves A's files.
        File.write("content/posts/a/index.md", "+++\ntitle = \"A\"\nslug = \"x\"\n+++\n")
        builder.run_incremental(["content/posts/a/index.md"], options)
        File.read("public/posts/x/index.html").should eq("A")
        File.read("public/posts/x/cover.png").should eq("A-cover")

        # Collision resolved: posts/x owns /posts/x/ again, files included.
        File.write("content/posts/a/index.md", "+++\ntitle = \"A\"\n+++\n")
        builder.run_incremental(["content/posts/a/index.md"], options)
        File.read("public/posts/x/index.html").should eq("X")
        File.read("public/posts/x/cover.png").should eq("X-cover")
        File.read("public/posts/a/cover.png").should eq("A-cover")
      end
    end
  end

  it "re-renders a page once the collision that suppressed it is gone" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        # `m` sits between `a` and `b` in date order, so `b` neither links
        # to `a` nor neighbours it: nothing but the collision ties them.
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\n+++\n")
        File.write("content/posts/m.md", "+++\ntitle = \"M\"\ndate = 2024-01-02\n+++\n")
        File.write("content/posts/m2.md", "+++\ntitle = \"M2\"\ndate = 2024-01-03\n+++\n")
        File.write("content/posts/b.md", "+++\ntitle = \"B\"\ndate = 2024-01-04\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/a.md"], options)

        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\nslug = \"b\"\n+++\n")
        builder.run_incremental(["content/posts/a.md"], options)
        File.read("public/posts/b/index.html").should eq("A")

        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\n+++\n")
        builder.run_incremental(["content/posts/a.md"], options)
        File.read("public/posts/a/index.html").should eq("A")
        File.read("public/posts/b/index.html").should eq("B")
      end
    end
  end
end

# `site.authors` embeds each page's title and summary; only the full build's
# Transform phase built it, so serve kept printing the pre-edit values.
describe "Builder serve passes and site.authors" do
  it "refreshes author page lists after a content edit and a shortcode edit" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/blog")
        FileUtils.mkdir_p("templates/shortcodes")
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/section.html", "A[{% for p in site.authors.ann.pages %}{{ p.title }}:{{ p.summary }}{% endfor %}]")
        File.write("templates/shortcodes/sc.html", "one")
        File.write("content/blog/_index.md", "+++\ntitle = \"B\"\n+++\n")
        post = "+++\ntitle = \"Old\"\nauthors = [\"ann\"]\n+++\nIntro {{ sc() }}\n\n<!-- more -->\n\nRest.\n"
        File.write("content/blog/post.md", post)

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/blog/post.md"], options)
        File.read("public/blog/index.html").should eq("A[Old:<p>Intro one</p>\n]")

        File.write("content/blog/post.md", post.sub("Old", "New").sub("Intro", "Lead"))
        builder.run_incremental(["content/blog/post.md"], options)
        File.read("public/blog/index.html").should eq("A[New:<p>Lead one</p>\n]")

        File.write("templates/shortcodes/sc.html", "two")
        builder.run_rerender(options)
        File.read("public/blog/index.html").should eq("A[New:<p>Lead two</p>\n]")
      end
    end
  end
end

describe "Builder#run_incremental listing fan-out" do
  it "refreshes sibling section.pages loops when a subsection's body changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/blog/sub")
        FileUtils.mkdir_p("templates")
        listing = "{% for p in section.pages %}[{{ p.title }}:{{ p.summary }}]{% endfor %}"
        File.write("templates/page.html", listing)
        File.write("templates/section.html", listing)
        File.write("content/blog/_index.md", "+++\ntitle = \"Blog\"\n+++\n")
        File.write("content/blog/sub/_index.md", "+++\ntitle = \"Sub\"\n+++\nold\n")
        File.write("content/blog/a.md", "+++\ntitle = \"A\"\n+++\na\n")
        File.write("content/blog/b.md", "+++\ntitle = \"B\"\n+++\nb\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/blog/sub/_index.md"], options)
        File.read("public/blog/a/index.html").should contain("<p>old</p>")

        # Only the subsection's body moves: its title, URL and the section
        # set are unchanged, so only the page-set projection can see it.
        File.write("content/blog/sub/_index.md", "+++\ntitle = \"Sub\"\n+++\nnew\n")
        builder.run_incremental(["content/blog/sub/_index.md"], options)
        File.read("public/blog/a/index.html").should contain("<p>new</p>")
        File.read("public/blog/b/index.html").should contain("<p>new</p>")
      end
    end
  end
end
