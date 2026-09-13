require "../../../spec_helper"
require "../../../../src/core/build/builder"
require "../../../../src/content/hooks"

# Build-level reporting and hook-failure contracts that only a real build
# exercises: what the receipt's "not published" count means, and which error
# class a failing `[build] hooks.pre` command produces.

private def build_site(&)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", <<-TOML)
        title = "T"
        base_url = "http://localhost"
        TOML
      FileUtils.mkdir_p("content")
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "<p>{{ content }}</p>")
      yield dir
    end
  end
end

private def run_build : Hwaro::Core::Build::Builder
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, highlight: false,
  ))
  builder
end

describe "build reporting" do
  # `pages_not_published` (the receipt's "N not published" row and the
  # `--json` key) counts PAGES that produced no output. A refused alias is
  # not one: the page itself is on disk, only one of its redirect stubs was
  # skipped — counting it made the build report a page it had published.
  it "does not count a page whose alias escapes as unpublished" do
    build_site do
      File.write("content/post.md", <<-MD)
        +++
        title = "Post"
        aliases = ["../../evil/"]
        +++
        body
        MD

      builder = run_build
      stats = builder.context.not_nil!.stats

      File.exists?("public/post/index.html").should be_true
      stats.pages_unpublished.should eq(0)
      stats.pages_rendered.should eq(1)
    end
  end

  it "still counts a page whose own url escapes as unpublished" do
    build_site do
      File.write("content/post.md", <<-MD)
        +++
        title = "Post"
        path = "../escape"
        +++
        body
        MD

      builder = run_build
      stats = builder.context.not_nil!.stats

      stats.pages_unpublished.should eq(1)
      stats.pages_rendered.should eq(0)
    end
  end
end

describe "build hooks" do
  # A user command listed in config.toml exiting non-zero is a configuration
  # failure, not an hwaro bug: returning `false` made the CLI synthesize
  # HWARO_E_INTERNAL / exit 70, the code CI reserves for internal faults.
  it "classifies a failing pre-build hook as HWARO_E_CONFIG" do
    build_site do
      File.write("content/post.md", "+++\ntitle = \"Post\"\n+++\nbody")
      File.write("config.toml", File.read("config.toml") +
                                "\n[build]\nhooks.pre = [\"exit 1\"]\n")

      err = expect_raises(Hwaro::HwaroError) { run_build }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      err.exit_code.should eq(Hwaro::Errors::EXIT_CONFIG)
      err.message.to_s.should contain("hooks.pre")
    end
  end

  it "keeps a failing post-build hook a warning, not a build failure" do
    build_site do
      File.write("content/post.md", "+++\ntitle = \"Post\"\n+++\nbody")
      File.write("config.toml", File.read("config.toml") +
                                "\n[build]\nhooks.post = [\"exit 1\"]\n")

      run_build
      File.exists?("public/post/index.html").should be_true
    end
  end
end
