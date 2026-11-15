require "../../../spec_helper"

private def autoescape_ids(dir : String, config_extra : String, templates : Bool = true) : Array(Hwaro::Services::Issue)
  FileUtils.mkdir_p(File.join(dir, "content"))
  File.write(File.join(dir, "config.toml"), %(title = "Site"\nbase_url = "https://example.com"\n#{config_extra}))
  if templates
    FileUtils.mkdir_p(File.join(dir, "templates"))
    File.write(File.join(dir, "templates", "page.html"), "{{ content }}")
    File.write(File.join(dir, "templates", "section.html"), "{{ content }}")
  end
  Hwaro::Services::Doctor.new(
    content_dir: File.join(dir, "content"),
    config_path: File.join(dir, "config.toml"),
    templates_dir: File.join(dir, "templates"),
    static_dir: File.join(dir, "static"),
  ).run.select { |i| i.id == "templates-autoescape-unset" }
end

describe "Doctor templates-autoescape-unset" do
  it "notes a site with its own templates that leaves [templates] autoescape unset" do
    Dir.mktmpdir do |dir|
      issues = autoescape_ids(dir, "")
      issues.size.should eq(1)
      issues[0].level.should eq(:info)
      issues[0].message.should contain("| safe")
      issues[0].message.should contain("autoescape = false")
    end
  end

  it "is quiet once the key is set either way, without templates, or when ignored" do
    ["[templates]\nautoescape = true\n", "[templates]\nautoescape = false\n",
     "[doctor]\nignore = [\"templates-autoescape-unset\"]\n"].each do |extra|
      Dir.mktmpdir { |dir| autoescape_ids(dir, extra).should be_empty }
    end
    Dir.mktmpdir { |dir| autoescape_ids(dir, "", templates: false).should be_empty }
  end
end
