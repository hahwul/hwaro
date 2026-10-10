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
