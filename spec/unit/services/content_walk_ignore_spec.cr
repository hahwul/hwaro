require "../../spec_helper"

# `[content] ignore` (#890) in the content-walking tools: every one of them
# must agree with the build that an ignored path does not exist.
class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def ignore_scan_for_test(dir : String) : Array(Link)
    find_internal_links(dir)
  end

  def ignore_resolve_for_test(links : Array(Link), content_dir : String) : Array(Result)
    check_internal_links(links, content_dir)
  end
end

private IGNORE_CONFIG = <<-TOML
  title = "t"
  base_url = "https://example.com"
  [content]
  ignore = ["README.md", "_templates", "docs/draft-notes"]
  TOML

# A project in a temp dir: one ignored root README, an ignored template
# folder (page + asset), an ignored nested directory, and real pages linking
# to all of them.
private def with_ignore_project(config : String = IGNORE_CONFIG, &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", config)
      {
        "content/index.md"                  => "+++\ntitle = \"Home\"\ndescription = \"d\"\n+++\n[r](/README/) [t](/_templates/note/) [i](/_templates/cover.png) [k](/docs/kept/)\n",
        "content/README.md"                 => "no front matter, broken [x](/nowhere/)\n",
        "content/_templates/note.md"        => "+++\ntitle = 3\n+++\n",
        "content/_templates/cover.png"      => "png",
        "content/_templates/orphan.png"     => "png",
        "content/docs/_index.md"            => "+++\ntitle = \"Docs\"\ndescription = \"d\"\n+++\n",
        "content/docs/kept.md"              => "+++\ntitle = \"Kept\"\ndescription = \"d\"\naliases = [\"/old-kept/\"]\n+++\n",
        "content/docs/draft-notes/a.md"     => "+++\ntitle = \"A\"\naliases = [\"/old-a/\"]\n+++\n",
        "content/docs/draft-notes/sub/b.md" => "+++\ntitle = \"B\"\n+++\n",
      }.each do |path, body|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      yield
    end
  end
end

private def ignored_name?(path : String) : Bool
  path.includes?("README") || path.includes?("_templates") || path.includes?("draft-notes")
end

describe "[content] ignore in the content tools" do
  it "drops ignored files from the shared walker" do
    with_ignore_project do
      files = Hwaro::Services::ContentWalk.find_content_files("content")
      files.should eq(["content/docs/_index.md", "content/docs/kept.md", "content/index.md"])
    end
  end

  it "keeps every file when the project has no ignore rules" do
    with_ignore_project(%(title = "t"\n)) do
      Hwaro::Services::ContentWalk.find_content_files("content").size.should eq(7)
    end
  end

  it "reads the rules of the config beside a foreign --content-dir" do
    with_ignore_project do
      FileUtils.mkdir_p("other/content")
      File.write("other/config.toml", %([content]\nignore = ["skip.md"]\n))
      File.write("other/content/skip.md", "x")
      File.write("other/content/keep.md", "x")
      Hwaro::Services::ContentWalk.find_content_files("other/content").should eq(["other/content/keep.md"])
    end
  end

  it "keeps ignored files out of tool list and tool stats" do
    with_ignore_project do
      paths = Hwaro::Services::ContentLister.new("content").list_all.map(&.path)
      paths.none? { |p| ignored_name?(p) }.should be_true
      paths.size.should eq(3)
    end
  end

  it "does not validate ignored files" do
    with_ignore_project do
      issues = Hwaro::Services::ContentValidator.new("content").run
      issues.none? { |i| ignored_name?(i.file.to_s) }.should be_true
    end
  end

  it "keeps doctor quiet about ignored files and directories" do
    with_ignore_project do
      issues = Hwaro::Services::Doctor.new(content_dir: "content", config_path: "config.toml").run
      issues.select { |i| ignored_name?(i.file.to_s) }.should be_empty
    end
  end

  it "reports links to ignored pages and files as dead, and does not scan ignored files" do
    with_ignore_project do
      command = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new
      links = command.ignore_scan_for_test("content")
      links.none? { |l| ignored_name?(l.file) }.should be_true
      dead = command.ignore_resolve_for_test(links, "content").map(&.link.url)
      dead.should contain("/README/")
      dead.should contain("/_templates/note/")
      dead.should contain("/_templates/cover.png")
      dead.should_not contain("/docs/kept/")
    end
  end

  it "never reports (or deletes) an ignored asset as unused" do
    with_ignore_project do
      result = Hwaro::Services::UnusedAssets.new(content_dir: "content", static_dir: "static", templates_dir: "templates").run
      result.unused_files.none? { |f| ignored_name?(f) }.should be_true
    end
  end

  # An ignored partial is still read by `include_md`, so an asset only it
  # names is published and must not be reported (or deleted) as unused.
  it "counts references from ignored Markdown a page includes" do
    with_ignore_project(%(title = "t"\n[content]\nignore = ["_partials/"]\n)) do
      FileUtils.mkdir_p("content/_partials")
      FileUtils.mkdir_p("static/img")
      File.write("static/img/only-in-partial.png", "png")
      File.write("content/_partials/snippet.md", "![x](/img/only-in-partial.png)\n")
      File.write("content/about.md", "+++\ntitle = \"About\"\n+++\n{{ include_md(path=\"content/_partials/snippet.md\") }}\n")
      result = Hwaro::Services::UnusedAssets.new(content_dir: "content", static_dir: "static", templates_dir: "templates").run
      result.unused_files.none?(&.includes?("only-in-partial")).should be_true
    end
  end

  it "exports neither ignored pages nor ignored assets" do
    with_ignore_project do
      Hwaro::Services::Exporters::HugoExporter.new.run(
        Hwaro::Config::Options::ExportOptions.new(target_type: "hugo", content_dir: "content", output_dir: "export"))
      exported = Dir.glob("export/**/*").select { |f| File.file?(f) }
      exported.should contain("export/content/docs/kept.md")
      exported.none? { |f| ignored_name?(f) }.should be_true
    end
  end

  it "emits no platform redirect for an ignored page's aliases" do
    with_ignore_project do
      config = Hwaro::Models::Config.load("config.toml")
      result = Hwaro::Services::PlatformConfig.new(config).generate("cloudflare")
      result.should contain("/old-kept/")
      result.should_not contain("/old-a/")
    end
  end

  # Patterns are written against the project's content/, so a walk of a
  # subdirectory (`-c content/blog`) must still read `blog/b.md` as
  # `blog/b.md`, not as `b.md`.
  it "matches patterns against the project content root when walking a subdirectory" do
    with_ignore_project(%([content]\nignore = ["blog/b.md", "README.md"]\n)) do
      FileUtils.mkdir_p("content/blog")
      File.write("content/blog/b.md", "x")
      File.write("content/blog/README.md", "x")
      Hwaro::Services::ContentWalk.find_content_files("content/blog").should eq(["content/blog/README.md"])
      Hwaro::Services::ContentLister.new("content/blog").list_all.map(&.path).should eq(["content/blog/README.md"])
    end
  end

  it "applies no rules to a directory outside the project's content root" do
    with_ignore_project(%([content]\nignore = ["**"]\n)) do
      FileUtils.mkdir_p("elsewhere")
      File.write("elsewhere/a.md", "x")
      Hwaro::Services::ContentWalk.find_content_files("elsewhere").should eq(["elsewhere/a.md"])
      Hwaro::Services::ContentWalk.find_content_files("content").should be_empty
    end
  end

  # `doctor --env X` validates what `build --env X` loads: the overlay's
  # ignore list must reach every content check, translations and
  # [[content.schema]] included, not the base config's.
  it "uses the --env overlay's ignore list in every doctor content check" do
    base = <<-TOML
      title = "t"
      base_url = "https://example.com"
      default_language = "en"
      [languages.en]
      [languages.ko]
      [[content.schema]]
      sections = "docs"
      [content.schema.fields.author]
      type = "string"
      required = true
      TOML
    with_ignore_project(base) do
      File.write("config.prod.toml", %([content]\nignore = ["docs/draft-notes", "docs/kept.md"]\n))
      ids = Hwaro::Services::Doctor.new(content_dir: "content", config_path: "config.toml", env: "prod").run
        .select { |i| i.file.to_s.includes?("draft-notes") || i.file.to_s.includes?("kept") }
        .map(&.id)
      ids.should be_empty

      # Control: the same checks do report those files without the overlay.
      flagged = Hwaro::Services::Doctor.new(content_dir: "content", config_path: "config.toml").run
        .select(&.file.to_s.includes?("kept")).map(&.id)
      flagged.should contain("translation-missing")
      flagged.should contain("content-schema-violation")
    end
  end

  # Doctor's referenced-path and version checks must not accept a file or
  # folder the build never reads.
  it "makes doctor report config paths that point into ignored content" do
    config = <<-TOML
      title = "My Site"
      base_url = "https://example.com"
      [content]
      ignore = ["raw.json", "docs/old/", "gone.md"]
      [og]
      default_image = "/raw.json"
      [pwa]
      enabled = true
      offline_page = "/gone/"
      [[versions.list]]
      name = "old"
      path = "docs/old"
      TOML
    with_ignore_project(config) do
      File.write("content/raw.json", "{}")
      File.write("content/gone.md", "+++\ntitle = \"Gone\"\n+++\n")
      FileUtils.mkdir_p("content/docs/old")
      File.write("content/docs/old/_index.md", "+++\ntitle = \"Old\"\n+++\n")
      messages = Hwaro::Services::Doctor.new(content_dir: "content", config_path: "config.toml").run.map(&.message)
      messages.any?(&.includes?("default_image")).should be_true
      messages.any? { |m| m.includes?("version \"old\"") && m.includes?("[content] ignore") }.should be_true
    end
  end

  # `_*` reads as "underscore folders" but also hides every `_index.md`.
  it "warns about an ignore pattern that hides section index files" do
    config = %(title = "t"\nbase_url = "https://example.com"\n[content]\nignore = ["_*", "**/_*/", "README.md"]\n)
    with_ignore_project(config) do
      issues = Hwaro::Services::Doctor.new(content_dir: "content", config_path: "config.toml").run
      warned = issues.select { |i| i.id == "content-ignore-hides-sections" }.map(&.message)
      warned.size.should eq(1)
      warned.first.should contain(%("_*"))
    end
  end
end
