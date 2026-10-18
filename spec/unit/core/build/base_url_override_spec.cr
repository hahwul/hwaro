require "../../../spec_helper"
require "file_utils"

describe "base_url override" do
  it "overrides config.toml base_url during build" do
    temp_dir = File.tempname("hwaro_base_url_override")
    Dir.mkdir(temp_dir)

    begin
      project_dir = File.join(temp_dir, "site")
      initializer = Hwaro::Services::Initializer.new
      initializer.run(Hwaro::Config::Options::InitOptions.new(
        path: project_dir,
        force: true,
        skip_agents_md: true,
        skip_sample_content: false,
        skip_taxonomies: true,
        multilingual_languages: [] of String,
        scaffold: Hwaro::Config::Options::ScaffoldType::Simple
      ))

      Dir.cd(project_dir) do
        builder = Hwaro::Core::Build::Builder.new
        builder.run(Hwaro::Config::Options::BuildOptions.new(base_url: "https://example.com"))

        robots_txt = File.join(project_dir, "public", "robots.txt")
        File.exists?(robots_txt).should be_true
        File.read(robots_txt).should contain("https://example.com")
      end
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  it "lets --base-url replace a base_url naming an unset variable" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "X"\nbase_url = "${HWARO_SPEC_UNSET_SITE_URL}"\n[sitemap]\nenabled = true\n))
        Dir.mkdir("content")
        File.write("content/index.md", "+++\ntitle = \"Home\"\n+++\nhi\n")

        with_captured_log do
          Hwaro::Core::Build::Builder.new.run(Hwaro::Config::Options::BuildOptions.new(base_url: "https://example.com", parallel: false))
        end
        File.read("public/sitemap.xml").should contain("<loc>https://example.com/</loc>")

        # Without an override the build still refuses, naming the variable.
        err = expect_raises(Hwaro::HwaroError, /HWARO_SPEC_UNSET_SITE_URL/) do
          with_captured_log do
            Hwaro::Core::Build::Builder.new.run(Hwaro::Config::Options::BuildOptions.new(parallel: false))
          end
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      end
    end
  end
end
