require "../../../../../spec_helper"

class Hwaro::Core::Build::Builder
  def test_sass_entry_outputs(config : Models::Config, output_dir : String) : Array(String)
    @config = config
    sass_entry_outputs(output_dir)
  end
end

describe "Builder#sass_entry_outputs" do
  # `ln -s loop.scss loop.scss` cannot be resolved (ELOOP): it is no entry,
  # and must not fail the build.
  it "skips an entry that is a looping symlink" do
    posix_only!("symlinks")
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("static")
        File.write("static/ok.scss", "a { b: c }")
        File.symlink("loop.scss", "static/loop.scss")
        config = Hwaro::Models::Config.new
        config.sass.enabled = true
        Hwaro::Core::Build::Builder.new.test_sass_entry_outputs(config, "public")
          .should eq([File.expand_path("public/ok.css")])
      end
    end
  end
end
