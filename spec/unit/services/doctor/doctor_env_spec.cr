require "../../../spec_helper"
require "../../../../src/services/doctor"

# doctor validates the same config as `hwaro build --env X`: the
# config.<env>.toml overlay is merged before the checks run.
private def env_site(dir : String) : Nil
  File.write(File.join(dir, "config.toml"), %(title = "S"\nbase_url = "https://example.com"\n))
  File.write(File.join(dir, "config.prod.toml"), %([csp]\nenabled = true\nmode = "bogus"\n))
  FileUtils.mkdir_p(File.join(dir, "content"))
end

private def env_doctor(dir : String, env : String?) : Hwaro::Services::Doctor
  Hwaro::Services::Doctor.new(
    content_dir: File.join(dir, "content"),
    config_path: File.join(dir, "config.toml"),
    templates_dir: File.join(dir, "templates"),
    env: env,
  )
end

describe "Doctor with an environment overlay" do
  it "reports an error that only the overlay introduces" do
    Dir.mktmpdir do |dir|
      env_site(dir)
      issues = env_doctor(dir, "prod").run
      issues.any? { |i| i.id == "config-parse-error" && i.message.includes?("csp") }.should be_true
    end
  end

  it "ignores the overlay when no environment is given" do
    Dir.mktmpdir do |dir|
      env_site(dir)
      env_doctor(dir, nil).run.any? { |i| i.id == "config-parse-error" }.should be_false
    end
  end

  it "exposes --env on the doctor command" do
    Hwaro::CLI::Commands::Tool::DoctorCommand.metadata.flags.any? { |f| f.long == "--env" }.should be_true
  end
end
