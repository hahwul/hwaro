require "../../../spec_helper"

describe "Hwaro::Models::Config boolean values" do
  it "warns when a boolean key holds a non-boolean value" do
    config = nil
    log = with_captured_log do
      config = load_config(%(title = "X"\n[markdown]\nsafe = "true"\n[feeds]\nenabled = "yes"\n))
    end
    config.not_nil!.markdown.safe.should be_false
    config.not_nil!.feeds.enabled.should be_false
    log.should contain(%(Ignoring non-boolean config value "true"))
    log.should contain(%(Ignoring non-boolean config value "yes"))
  end

  it "warns for the [content.new] and [deployment] switches too" do
    config = nil
    log = with_captured_log do
      config = load_config(%(title = "X"\n[content.new]\nbundle = "true"\n[deployment]\ndry_run = "yes"\n))
    end
    config.not_nil!.content_new.bundle.should be_false
    config.not_nil!.deployment.dry_run.should be_false
    log.should contain(%(Ignoring non-boolean config value "true"))
    log.should contain(%(Ignoring non-boolean config value "yes"))
  end

  it "applies real booleans, including false, without a warning" do
    config = nil
    log = with_captured_log do
      config = load_config(%(title = "X"\n[markdown]\nsafe = true\nfootnotes = false\n[feeds]\ngenerate = true\n))
    end
    config.not_nil!.markdown.safe.should be_true
    config.not_nil!.markdown.footnotes.should be_false
    config.not_nil!.feeds.enabled.should be_true
    log.should_not contain("non-boolean")
  end
end

describe "Hwaro::Models::Config array-of-tables options" do
  it "warns when an array-of-tables option is written as a single table" do
    config = nil
    log = with_captured_log do
      config = load_config(<<-TOML)
        title = "X"
        [robots.rules]
        user_agent = "*"
        disallow = "/private/"
        [menus.main]
        name = "Home"
        url = "/"
        [assets.bundles]
        name = "main.css"
        files = ["a.css"]
        [deployment.targets]
        name = "prod"
        url = "file:///tmp/prod"
        TOML
    end
    config.not_nil!.robots.rules.should be_empty
    log.should contain("Ignoring robots.rules: it must be an array of tables — write each entry as [[robots.rules]].")
    log.should contain("Ignoring menus.main:")
    log.should contain("Ignoring assets.bundles:")
    log.should contain("Ignoring deployment.targets:")
  end

  it "reads [[...]] entries without a warning" do
    config = nil
    log = with_captured_log do
      config = load_config(%(title = "X"\n[[robots.rules]]\nuser_agent = "*"\ndisallow = "/private/"\n[[menus.main]]\nname = "Home"\n))
    end
    config.not_nil!.robots.rules.map(&.disallow).should eq([["/private/"]])
    config.not_nil!.menus["main"].map(&.name).should eq(["Home"])
    log.should_not contain("array of tables")
  end
end
