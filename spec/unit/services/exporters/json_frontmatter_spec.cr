require "../../../spec_helper"

describe "JSON frontmatter export" do
  [Hwaro::Services::Exporters::HugoExporter, Hwaro::Services::Exporters::JekyllExporter].each do |exporter_type|
    describe exporter_type do
      it "preserves Unicode metadata, nested values, post dates, and the body" do
        Dir.mktmpdir do |dir|
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(File.join(content_dir, "posts"))
          header = %({"title":"한글 } 글","date":"2024-01-02","draft":false,"extra":{"rating":2.5,"id":99999999999,"enabled":true,"label":"false","items":[1,"둘"],"empty":[]}})
          File.write(File.join(content_dir, "posts", "hello.md"), "\uFEFF#{header}\n\n본문입니다.\n")
          output_dir = File.join(dir, "export")
          result = exporter_type.new.run(Hwaro::Config::Options::ExportOptions.new(content_dir: content_dir, output_dir: output_dir))

          result.success.should be_true
          result.exported_count.should eq(1)
          relative = exporter_type == Hwaro::Services::Exporters::HugoExporter ? "content/posts/hello.md" : "_posts/2024-01-02-hello.md"
          exported = File.read(File.join(output_dir, relative))
          dialect, header_text = Hwaro::Utils::FrontmatterScanner.detect(exported).not_nil!
          fields = if dialect == :toml
                     TOML.parse(header_text).transform_values { |value| Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(value) }
                   else
                     YAML.parse(header_text).as_h.transform_keys(&.as_s)
                   end
          fields["title"].as_s.should eq("한글 } 글")
          fields["extra"]["rating"].as_f.should eq(2.5)
          fields["extra"]["id"].as_i64.should eq(99999999999_i64)
          fields["extra"]["enabled"].as_bool.should be_true
          fields["extra"]["label"].as_s.should eq("false")
          fields["extra"]["items"].as_a.map(&.to_s).should eq(["1", "둘"])
          fields["extra"]["empty"].as_a.should be_empty
          Hwaro::Utils::FrontmatterScanner.strip_frontmatter(exported).strip.should eq("본문입니다.")
        end
      end

      it "skips JSON drafts by default and exports them when requested" do
        Dir.mktmpdir do |dir|
          content_dir = File.join(dir, "content")
          FileUtils.mkdir_p(File.join(content_dir, "posts"))
          File.write(File.join(content_dir, "posts", "secret.md"), %({"title":"Secret","date":"2024-01-02","draft":true}\n\nSecret body.))
          output_dir = File.join(dir, "export")
          options = Hwaro::Config::Options::ExportOptions.new(content_dir: content_dir, output_dir: output_dir)
          result = exporter_type.new.run(options)
          result.success.should be_true
          result.exported_count.should eq(0)
          result.skipped_count.should eq(1)
          Dir.glob(File.join(output_dir, "**", "*.md")).should be_empty

          options.drafts = true
          result = exporter_type.new.run(options)
          result.success.should be_true
          result.exported_count.should eq(1)
          relative = exporter_type == Hwaro::Services::Exporters::HugoExporter ? "content/posts/secret.md" : "_drafts/secret.md"
          exported = File.read(File.join(output_dir, relative))
          exported.should contain(exporter_type == Hwaro::Services::Exporters::HugoExporter ? "draft = true" : "published: false")
        end
      end

      [%( {"title": broken}), %({"draft":true)].each do |header|
        it "reports malformed JSON as an export error: #{header}" do
          Dir.mktmpdir do |dir|
            content_dir = File.join(dir, "content")
            FileUtils.mkdir_p(content_dir)
            File.write(File.join(content_dir, "broken.md"), "#{header.strip}\n\nBody.")
            output_dir = File.join(dir, "export")
            result = exporter_type.new.run(Hwaro::Config::Options::ExportOptions.new(content_dir: content_dir, output_dir: output_dir))
            result.success.should be_false
            result.exported_count.should eq(0)
            result.error_count.should eq(1)
            Dir.glob(File.join(output_dir, "**", "*.md")).should be_empty
          end
        end
      end

      ["{{ youtube(id=\"example\") }}\nBody.", "{:.wide}\nBody.", "{% if true %}Body.{% endif %}"].each do |body|
        it "preserves brace-prefixed Markdown content: #{body}" do
          Dir.mktmpdir do |dir|
            content_dir = File.join(dir, "content")
            FileUtils.mkdir_p(content_dir)
            File.write(File.join(content_dir, "page.md"), body)
            output_dir = File.join(dir, "export")
            result = exporter_type.new.run(Hwaro::Config::Options::ExportOptions.new(content_dir: content_dir, output_dir: output_dir))
            result.success.should be_true
            result.exported_count.should eq(1)
            exported = File.read(Dir.glob(File.join(output_dir, "**", "*.md")).first)
            Hwaro::Utils::FrontmatterScanner.strip_frontmatter(exported).strip.should eq(body)
          end
        end
      end
    end
  end
end
