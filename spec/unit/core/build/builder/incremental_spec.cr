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
end
