require "../../../spec_helper"

describe "Hwaro::Models::Config [deployment] loader" do
  it "warns about a target without a name instead of dropping it silently" do
    config = nil
    log = with_captured_log do
      config = load_config(<<-TOML)
        [[deployment.targets]]
        url = "file:///tmp/nameless"

        [[deployment.targets]]
        name = "prod"
        url = "file:///tmp/prod"
        TOML
    end
    config.not_nil!.deployment.targets.map(&.name).should eq(["prod"])
    log.should contain("[[deployment.targets]] entry #1")
    log.should contain("no string 'name'")
  end

  it "accepts stripIndexHTML = false without calling it a non-boolean" do
    config = nil
    log = with_captured_log do
      config = load_config(<<-TOML)
        [[deployment.targets]]
        name = "prod"
        url = "file:///tmp/prod"
        stripIndexHTML = false

        [[deployment.targets]]
        name = "bad"
        url = "file:///tmp/bad"
        strip_index_html = "yes"
        TOML
    end
    config.not_nil!.deployment.targets.map(&.strip_index_html).should eq([false, false])
    log.should_not contain("prod: 'stripIndexHTML' must be a boolean")
    log.should contain("bad: 'stripIndexHTML' must be a boolean")
  end
end
