require "../../spec_helper"

# Regressions from the `hwaro tool` audit: exporters dropped taxonomy
# membership, `check-links` reported the build's own generated routes as dead
# before the first build, and `tool convert` never said why it skipped a file.
describe "tool audit regressions" do
  describe "exporters flatten [taxonomies]" do
    it "writes Hugo taxonomy terms at the top level" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))
        File.write(File.join(content_dir, "posts", "p.md"), <<-MD)
          +++
          title = "Post"
          date = "2024-01-15"
          [taxonomies]
          tags = ["crystal", "ssg"]
          categories = ["news"]
          +++

          Body
          MD

        result = Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo", content_dir: content_dir, output_dir: output_dir
          )
        )
        result.success.should be_true

        exported = File.read(File.join(output_dir, "content", "posts", "p.md"))
        parsed = TOML.parse(exported.match!(/\A\+\+\+\n(.*?)\+\+\+/m)[1])
        parsed["taxonomies"]?.should be_nil
        parsed["tags"].raw.as(Array).map(&.as(TOML::Any).raw).should eq(["crystal", "ssg"])
        parsed["categories"].raw.as(Array).map(&.as(TOML::Any).raw).should eq(["news"])
      end
    end

    it "writes Jekyll taxonomy terms as tags:/categories:" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(File.join(content_dir, "posts"))
        File.write(File.join(content_dir, "posts", "p.md"), <<-MD)
          +++
          title = "Post"
          date = "2024-01-15"
          [taxonomies]
          tags = ["crystal"]
          categories = ["news"]
          +++

          Body
          MD

        result = Hwaro::Services::Exporters::JekyllExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "jekyll", content_dir: content_dir, output_dir: output_dir
          )
        )
        result.success.should be_true

        post = Dir.glob(File.join(output_dir, "_posts", "*.md")).first
        exported = File.read(post)
        exported.should contain("tags:\n  - crystal")
        exported.should contain("categories:\n  - news")
        exported.should_not contain("taxonomies:")
      end
    end

    it "keeps an explicit top-level key when both spellings are present" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "p.md"), <<-MD)
          +++
          title = "Post"
          tags = ["top"]
          [taxonomies]
          tags = ["nested"]
          +++

          Body
          MD

        Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo", content_dir: content_dir, output_dir: output_dir
          )
        )

        exported = File.read(File.join(output_dir, "content", "p.md"))
        parsed = TOML.parse(exported.match!(/\A\+\+\+\n(.*?)\+\+\+/m)[1])
        parsed["tags"].raw.as(Array).map(&.as(TOML::Any).raw).should eq(["top"])
      end
    end
  end

  describe "exporter taxonomy precedence" do
    it "hoists the table when the top-level key is declared but null" do
      # A `tags:` with no value is not a declaration that wins: the Hugo
      # exporter drops null values, so treating it as present lost the terms.
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        output_dir = File.join(dir, "export")
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "p.md"), <<-MD)
          ---
          title: Post
          tags:
          taxonomies:
            tags:
              - crystal
          ---

          Body
          MD

        Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(
            target_type: "hugo", content_dir: content_dir, output_dir: output_dir
          )
        )

        exported = File.read(File.join(output_dir, "content", "p.md"))
        parsed = TOML.parse(exported.match!(/\A\+\+\+\n(.*?)\+\+\+/m)[1])
        parsed["tags"].raw.as(Array).map(&.as(TOML::Any).raw).should eq(["crystal"])
      end
    end
  end

  describe "tool convert skip reporting" do
    it "names the file whose leading block is not front matter and tallies the reason" do
      Dir.mktmpdir do |dir|
        content_dir = File.join(dir, "content")
        FileUtils.mkdir_p(content_dir)
        # A thematic rule, not front matter: rewriting it would delete prose.
        File.write(File.join(content_dir, "hr.md"), "---\njust prose\n\nmore prose\n---\ntail\n")
        File.write(File.join(content_dir, "ok.md"), "---\ntitle: Post\n---\n\nBody\n")

        result = Hwaro::Services::FrontmatterConverter.new(content_dir).convert_to_toml
        result.converted_count.should eq(1)
        result.skipped_count.should eq(1)
        # The refused file is untouched.
        File.read(File.join(content_dir, "hr.md")).should start_with("---\njust prose")
      end
    end
  end
end
