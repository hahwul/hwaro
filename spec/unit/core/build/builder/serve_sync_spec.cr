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
end
