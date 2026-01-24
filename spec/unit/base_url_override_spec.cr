require "../spec_helper"
require "file_utils"

describe "base_url override" do
  it "overrides config.toml base_url during build" do
    temp_dir = File.tempname("hwaro_base_url_override")
    Dir.mkdir(temp_dir)

    begin
      project_dir = File.join(temp_dir, "site")
      initializer = Hwaro::Services::Initializer.new
      initializer.run(
        target_path: project_dir,
        force: true,
        skip_agents_md: true,
        skip_sample_content: false,
        skip_taxonomies: true,
        multilingual_languages: [] of String,
        scaffold_type: Hwaro::Config::Options::ScaffoldType::Simple
      )

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
end
