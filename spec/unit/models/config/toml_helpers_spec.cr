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
