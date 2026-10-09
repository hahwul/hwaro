require "../../../../spec_helper"

class Hwaro::CLI::Commands::Tool::DeadlinkCommand
  def config_load_for_test(project_root : String) : Hwaro::Models::Config?
    load_config(project_root)
  end
end

describe "check-links config loading" do
  it "returns nil only when config.toml is absent" do
    Dir.mktmpdir do |dir|
      Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.config_load_for_test(dir).should be_nil
    end
  end

  it "loads a valid config.toml" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.toml"), %(title = "T"\nbase_url = "http://x"\n))
      config = Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.config_load_for_test(dir)
      config.not_nil!.title.should eq("T")
    end
  end

  # A swallowed load error replaced the config with defaults (no taxonomies,
  # base_path, languages), so /tags/ etc. were reported as dead links.
  it "raises HWARO_E_CONFIG for a broken config.toml instead of using defaults" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.toml"), %(title = "T"\noops = = 1\n))
      err = expect_raises(Hwaro::HwaroError) do
        Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.config_load_for_test(dir)
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end
  end

  it "raises HWARO_E_CONFIG for a config.toml with invalid UTF-8" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.toml"), Bytes[0x74, 0x3d, 0x22, 0xff, 0xfe, 0x22, 0x0a])
      expect_raises(Hwaro::HwaroError) do
        Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.config_load_for_test(dir)
      end
    end
  end
end
