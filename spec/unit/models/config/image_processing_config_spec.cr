require "../../../spec_helper"

describe Hwaro::Models::ImageProcessingConfig do
  it "writes no extra formats by default" do
    Hwaro::Models::Config.new.image_processing.formats.should be_empty
  end

  it "parses formats, case-insensitively and without duplicates" do
    config = load_config(<<-TOML)
      [image_processing]
      enabled = true
      formats = ["WebP", "webp"]
      TOML
    config.image_processing.formats.should eq(["webp"])
  end

  it "rejects an unknown format" do
    err = expect_config_error(<<-TOML)
      [image_processing]
      formats = ["avif"]
      TOML
    err.message.to_s.should contain(%(unknown format "avif"))
  end

  it "rejects formats that are not an array" do
    err = expect_config_error(<<-TOML)
      [image_processing]
      formats = "webp"
      TOML
    err.message.to_s.should contain("must be an array")
  end
end
