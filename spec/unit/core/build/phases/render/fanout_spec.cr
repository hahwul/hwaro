require "../../../../../spec_helper"

private def chmod_tree(root : String, mode : Int32)
  Dir.glob(File.join(root, "**", "*")).each { |p| File.chmod(p, mode) if Dir.exists?(p) }
  File.chmod(root, mode)
end

private def new_builder : Hwaro::Core::Build::Builder
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder
end

private def run_write_failure_build(parallel : Bool) : Hwaro::HwaroError
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      File.write("config.toml", "title = \"T\"\nbase_url = \"http://localhost\"\n")
      FileUtils.mkdir_p("templates")
      File.write("templates/page.html", "{{ content }}")
      FileUtils.mkdir_p("content")
      File.write("content/a.md", "+++\ntitle = \"A\"\n+++\na\n")
      File.write("content/b.md", "+++\ntitle = \"B\"\n+++\nb\n")

      new_builder.run(Hwaro::Config::Options::BuildOptions.new(parallel: parallel))
      # A read-only output tree: every page write is denied.
      chmod_tree("public", 0o555)
      begin
        expect_raises(Hwaro::HwaroError) do
          new_builder.run(Hwaro::Config::Options::BuildOptions.new(parallel: parallel))
        end
      ensure
        chmod_tree("public", 0o755)
      end
    end
  end
end

describe "Render fan-out write failures" do
  # A permission-denied page write is an environment problem: exit 6
  # (HWARO_E_IO), not exit 4 "Render failed" (HWARO_E_TEMPLATE).
  it "classifies a denied page write as HWARO_E_IO (parallel)" do
    run_write_failure_build(parallel: true).code.should eq(Hwaro::Errors::HWARO_E_IO)
  end

  it "classifies a denied page write as HWARO_E_IO (sequential)" do
    run_write_failure_build(parallel: false).code.should eq(Hwaro::Errors::HWARO_E_IO)
  end
end
