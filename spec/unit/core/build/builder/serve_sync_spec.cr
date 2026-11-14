require "../../../../spec_helper"
require "../../../../../src/core/build/builder"
require "../../../../../src/content/hooks"

# Serve republishes an edited non-page `content/` file through
# `copy_changed_content_files`; it must publish exactly what the build's raw
# lane publishes (Phases::ReadContent#publishes_content_file?).
private def republish(config : String, files : Hash(String, String), edit : Hash(String, String), &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", config)
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "{{ content }}")
      files.each do |path, body|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      builder = Hwaro::Core::Build::Builder.new
      Hwaro::Content::Hooks.all.each { |hook| builder.register(hook) }
      builder.run(Hwaro::Config::Options::BuildOptions.new(highlight: false)).should be_true
      edit.each { |path, body| File.write(path, body) }
      builder.copy_changed_content_files(edit.keys, "public", false)
      yield
    end
  end
end

describe "Builder#copy_changed_content_files" do
  it "republishes an edited raw JSON file without an allow_extensions entry" do
    republish("title = \"T\"\nbase_url = \"http://localhost\"\n",
      {"content/docs/data.json" => %({"v": 1})},
      {"content/docs/data.json" => %({"v": 2})}) do
      File.read("public/docs/data.json").should eq(%({"v": 2}))
    end
  end

  it "keeps a denied raw JSON file unpublished" do
    republish("title = \"T\"\nbase_url = \"http://localhost\"\n\n[content.files]\ndisallow_paths = [\"private/**\"]\n",
      {"content/private/secret.json" => %({"v": 1})},
      {"content/private/secret.json" => %({"v": 2})}) do
      File.exists?("public/private/secret.json").should be_false
    end
  end

  it "does not count a collision loser's bundle file as copied" do
    log = with_captured_log do
      republish("title = \"T\"\nbase_url = \"http://localhost\"\n",
        {"content/posts/a/index.md"  => "+++\ntitle = \"A\"\nslug = \"x\"\n+++\n",
         "content/posts/x/index.md"  => "+++\ntitle = \"X\"\n+++\n",
         "content/posts/x/xonly.png" => "1"},
        {"content/posts/x/xonly.png" => "2"}) do
        File.exists?("public/posts/x/xonly.png").should be_false
      end
    end
    log.should_not contain("copied")
  end
end

# #859: a same-size save in the tick of the last copy keeps the copy's stamp;
# the serve cache is off, so only the watcher knows the bundle asset changed.
describe "Builder#copy_changed_content_files and bundle assets" do
  it "republishes a changed asset whose size and mtime still match the copy" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost\"\n")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}")
        FileUtils.mkdir_p("content/post")
        File.write("content/post/index.md", "---\ntitle: Post\n---\nPost")
        File.write("content/post/data.txt", "VERSION_A")
        settled = Time.utc - 1.hour
        File.touch("content/post/data.txt", settled)
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |hook| builder.register(hook) }
        builder.run(Hwaro::Config::Options::BuildOptions.new(highlight: false)).should be_true
        File.info("public/post/data.txt").modification_time.should eq(settled)

        File.write("content/post/data.txt", "VERSION_B")
        File.touch("content/post/data.txt", settled)
        builder.copy_changed_content_files(["content/post/data.txt"], "public", false)
        File.read("public/post/data.txt").should eq("VERSION_B")
      end
    end
  end
end

describe "Builder serve passes and the date filter's locale warning" do
  it "warns about an unknown date locale again on each incremental serve pass" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.date | date(format='%B', locale='xx') }}")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        2.times do |pass|
          File.write("content/a.md", "+++\ntitle = \"A#{pass}\"\ndate = \"2024-03-05\"\n+++\n")
          log = with_captured_log { builder.run_incremental(["content/a.md"], options) }
          log.should contain(%(unknown locale "xx"))
          File.read("public/a/index.html").should eq("March")
        end
      end
    end
  end
end

# The `resize_image(op=…)` memo lived for the whole serve process and was
# only cleared by a full build: a template edit that dropped a variant let
# the sweep delete it, and the edit that brought it back hit the memo and
# never wrote the file — every page pointed at a 404 image.
describe "Builder serve passes and resize_image op variants" do
  it "writes a variant again after a template edit removed and restored it" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        FileUtils.mkdir_p("static/img")
        pixels = Bytes.new(40 * 30 * 3) { |i| (i % 251).to_u8 }
        LibStb.stbi_write_png("static/img/photo.png", 40, 30, 3, pixels.to_unsafe.as(Void*), 40 * 3).should_not eq(0)
        File.touch("static/img/photo.png", Time.utc(2020, 1, 1))
        File.write("content/a.md", "+++\ntitle = \"A\"\n+++\n")
        tpl = ->(op : String) { File.write("templates/page.html", %({% set f = resize_image(path="/img/photo.png", width=10, height=12, op="#{op}") %}{{ f.url }})) }
        variant = "public/img/photo_10x12_fill_center.png"

        tpl.call("fill")
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |hook| builder.register(hook) }
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        builder.run(options).should be_true
        File.exists?(variant).should be_true

        options.preserve_output = true
        tpl.call("fit")
        builder.run_rerender(options)
        File.exists?(variant).should be_false

        tpl.call("fill")
        builder.run_rerender(options)
        File.read("public/a/index.html").should eq("http://localhost/img/photo_10x12_fill_center.png")
        File.exists?(variant).should be_true
      end
    end
  end
end
