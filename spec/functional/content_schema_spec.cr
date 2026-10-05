require "../support/build_helper"

# End-to-end `[[content.schema]]`: the build applies defaults before render,
# fails once with every violation, and doctor / `tool validate` report the
# same violations as the build.

private SCHEMA_CONFIG = <<-TOML
  title = "Schema"
  base_url = "http://localhost"

  [[content.schema]]
  sections = ["posts"]

  [content.schema.fields.author]
  type = "string"
  required = true

  [content.schema.fields.status]
  type = "string"
  enum = ["draft", "review", "final"]
  default = "draft"

  [content.schema.fields.description]
  type = "string"
  default = "No description."

  [content.schema.fields."extra.rating"]
  type = "int"
  min = 1
  max = 5

  [[content.schema]]
  sections = ["**"]
  strict = true
  TOML

private SCHEMA_TEMPLATES = {
  "page.html"    => "status={{ page.extra.status }} author={{ page.extra.author }} desc={{ page.description }}",
  "section.html" => "{{ section.title }}",
  "index.html"   => "home",
}

private def violation_lines(err : Hwaro::HwaroError) : Array(String)
  err.message.to_s.lines.skip(1).map(&.strip)
end

private def tool_violation_lines(content_dir = "content") : Array(String)
  config = Hwaro::Models::Config.load
  Hwaro::Services::Doctor.content_schema_results(content_dir, config).flat_map(&.[1].violations.map(&.to_s))
end

describe "[[content.schema]] build" do
  it "applies defaults that templates see, with cascaded values counting as present" do
    build_site(SCHEMA_CONFIG,
      content_files: {
        "posts/_index.md" => "+++\ntitle = \"Posts\"\n[cascade.extra]\nauthor = \"cascaded\"\n+++\n",
        "posts/a.md"      => "+++\ntitle = \"A\"\n+++\nbody\n",
        "posts/b.md"      => "+++\ntitle = \"B\"\nauthor = \"me\"\nstatus = \"final\"\ndescription = \"Mine\"\n+++\nbody\n",
      },
      template_files: SCHEMA_TEMPLATES) do
      File.read("public/posts/a/index.html").should eq("status=draft author=cascaded desc=No description.")
      File.read("public/posts/b/index.html").should eq("status=final author=me desc=Mine")
    end
  end

  it "fails once with every violation across pages (HWARO_E_CONTENT), sorted by file" do
    err = expect_raises(Hwaro::HwaroError) do
      build_site(SCHEMA_CONFIG,
        content_files: {
          "posts/b.md" => "+++\ntitle = \"B\"\nauthor = 7\nstatus = \"done\"\n[extra]\nrating = 9\n+++\n",
          "posts/a.md" => "+++\ntitle = \"A\"\n+++\n",
          "about.md"   => "+++\ntitle = \"About\"\nautor = \"x\"\n+++\n",
        },
        template_files: SCHEMA_TEMPLATES) { }
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
    violation_lines(err).should eq([
      %(content/about.md:3: field "autor": unknown front-matter key — did you mean "authors"?),
      %(content/posts/a.md: field "author": required but missing),
      %(content/posts/b.md:3: field "author": expected string, got int),
      %(content/posts/b.md:4: field "status": "done" is not one of "draft", "review", "final"),
      %(content/posts/b.md:6: field "extra.rating": 9 is greater than the maximum 5),
    ])
  end

  it "uses the first matching schema only" do
    # posts/ matches both entries; the first (non-strict) wins, so the
    # unknown key is not an error there while the root page's is.
    build_site(SCHEMA_CONFIG,
      content_files: {"posts/a.md" => "+++\ntitle = \"A\"\nauthor = \"me\"\nfreeform = 1\n+++\n"},
      template_files: SCHEMA_TEMPLATES) do
      File.exists?("public/posts/a/index.html").should be_true
    end
  end

  it "does not validate section index files or unpublished drafts" do
    build_site(SCHEMA_CONFIG,
      content_files: {
        "posts/_index.md" => "+++\ntitle = \"Posts\"\n+++\n",
        "posts/wip.md"    => "+++\ntitle = \"WIP\"\ndraft = true\n+++\n",
      },
      template_files: SCHEMA_TEMPLATES) do
      File.exists?("public/posts/index.html").should be_true
    end
  end

  it "keeps applied defaults on a warm --cache build" do
    build_site(SCHEMA_CONFIG,
      content_files: {
        "posts/a.md" => "+++\ntitle = \"A\"\nauthor = \"me\"\n+++\n",
        "posts/b.md" => "+++\ntitle = \"B\"\nauthor = \"me\"\n+++\n",
      },
      template_files: SCHEMA_TEMPLATES, cache: true) do
      File.read("public/posts/a/index.html").should contain("status=draft")
      # Warm build: b.md changes, a.md is a cache hit, and the listing-level
      # page data still carries a.md's default.
      File.write("content/posts/b.md", "+++\ntitle = \"B2\"\nauthor = \"me\"\n+++\n")
      builder = Hwaro::Core::Build::Builder.new
      builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true))
      builder.site.not_nil!.pages.find! { |p| p.path == "posts/a.md" }.extra["status"].should eq("draft")
      File.read("public/posts/a/index.html").should contain("status=draft")
      File.read("public/posts/b/index.html").should contain("status=draft")
    end
  end

  it "doctor and tool validate report the same violations as the build" do
    files = {
      "posts/_index.md" => "+++\ntitle = \"Posts\"\n[cascade.extra]\nauthor = \"cascaded\"\n+++\n",
      "posts/a.md"      => "+++\ntitle = \"A\"\nstatus = \"nope\"\n+++\n",
      "posts/wip.md"    => "+++\ntitle = \"W\"\ndraft = true\nstatus = \"nope\"\n+++\n",
      "about.md"        => "---\ntitle: About\nautor: x\n---\n",
    }
    build_lines = [] of String
    begin
      build_site(SCHEMA_CONFIG, content_files: files, template_files: SCHEMA_TEMPLATES) { }
    rescue ex : Hwaro::HwaroError
      build_lines = violation_lines(ex)
    end
    build_lines.size.should eq(2)

    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", SCHEMA_CONFIG)
        files.each do |path, body|
          FileUtils.mkdir_p(File.dirname(File.join("content", path)))
          File.write(File.join("content", path), body)
        end
        tool_violation_lines.sort.should eq(build_lines)

        issues = Hwaro::Services::Doctor.new.run.select { |i| i.id == "content-schema-violation" }
        issues.map { |i| {i.file.to_s, i.line, i.level} }.sort_by!(&.[0]).should eq([
          {"content/about.md", 3, :error},
          {"content/posts/a.md", 3, :error},
        ])
      end
    end
  end
end

private def run_schema_cli(args : Array(String), dir : String) : {Int32, String}
  output = IO::Memory.new
  status = Process.run(hwaro_binary, args, chdir: dir, output: output, error: output)
  {status.exit_code, output.to_s}
end

describe "[[content.schema]] CLI" do
  it "exits 3 on a malformed schema and 5 on violations; validate --json carries both violations and defaults" do
    pending!("bin/hwaro missing (run shards build)") unless File.exists?(hwaro_binary)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.toml"), SCHEMA_CONFIG.sub(%(type = "int"), %(type = "integer")))
      FileUtils.mkdir_p(File.join(dir, "content/posts"))
      File.write(File.join(dir, "content/posts/a.md"), "+++\ntitle = \"A\"\n+++\n")
      File.write(File.join(dir, "content/posts/b.md"), "+++\ntitle = \"B\"\nauthor = 1\n+++\n")
      SCHEMA_TEMPLATES.each { |name, body| FileUtils.mkdir_p(File.join(dir, "templates")); File.write(File.join(dir, "templates", name), body) }

      code, text = run_schema_cli(["build"], dir)
      code.should eq(Hwaro::Errors::EXIT_CONFIG)
      text.should contain("unknown type 'integer'")

      File.write(File.join(dir, "config.toml"), SCHEMA_CONFIG)
      code, text = run_schema_cli(["build"], dir)
      code.should eq(Hwaro::Errors::EXIT_CONTENT)
      text.should contain(%(content/posts/a.md: field "author": required but missing))
      text.should contain(%(content/posts/b.md:3: field "author": expected string, got int))

      code, text = run_schema_cli(["tool", "validate", "--json"], dir)
      code.should eq(Hwaro::Errors::EXIT_CONTENT)
      json = JSON.parse(text)
      schema = json["findings"].as_a.select { |f| f["rule"] == "content-schema-violation" }
      schema.map { |f| {f["file"].as_s, f["line"].as_i?} }.should eq([{"content/posts/a.md", nil}, {"content/posts/b.md", 3}])
      json["defaults"]["content/posts/a.md"]["status"].should eq("draft")
      json["defaults"]["content/posts/a.md"]["description"].should eq("No description.")
    end
  end
end
