require "../spec_helper"
require "../../src/utils/errors"

describe Hwaro::Errors do
  describe ".category_for" do
    it "maps known codes to their category" do
      Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_USAGE).should eq(:usage)
      Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_CONFIG).should eq(:config)
      Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_TEMPLATE).should eq(:template)
      Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_CONTENT).should eq(:content)
      Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_IO).should eq(:io)
      Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_NETWORK).should eq(:network)
      Hwaro::Errors.category_for(Hwaro::Errors::HWARO_E_INTERNAL).should eq(:internal)
    end

    it "falls back to :internal for unknown codes" do
      Hwaro::Errors.category_for("HWARO_E_UNSEEN").should eq(:internal)
    end
  end

  describe ".exit_for" do
    it "maps codes to their documented exit code" do
      Hwaro::Errors.exit_for(Hwaro::Errors::HWARO_E_USAGE).should eq(2)
      Hwaro::Errors.exit_for(Hwaro::Errors::HWARO_E_CONFIG).should eq(3)
      Hwaro::Errors.exit_for(Hwaro::Errors::HWARO_E_TEMPLATE).should eq(4)
      Hwaro::Errors.exit_for(Hwaro::Errors::HWARO_E_CONTENT).should eq(5)
      Hwaro::Errors.exit_for(Hwaro::Errors::HWARO_E_IO).should eq(6)
      Hwaro::Errors.exit_for(Hwaro::Errors::HWARO_E_NETWORK).should eq(7)
      Hwaro::Errors.exit_for(Hwaro::Errors::HWARO_E_INTERNAL).should eq(70)
    end

    it "falls back to the legacy generic exit for unknown codes" do
      Hwaro::Errors.exit_for("HWARO_E_UNSEEN").should eq(1)
    end
  end
end

describe Hwaro::HwaroError do
  it "stores code, derived category, message, hint" do
    err = Hwaro::HwaroError.new(
      code: Hwaro::Errors::HWARO_E_USAGE,
      message: "missing <path> argument",
      hint: "run hwaro new --help",
    )

    err.code.should eq("HWARO_E_USAGE")
    err.category.should eq(:usage)
    err.message.should eq("missing <path> argument")
    err.hint.should eq("run hwaro new --help")
    err.exit_code.should eq(2)
  end

  it "defaults hint to nil" do
    err = Hwaro::HwaroError.new(
      code: Hwaro::Errors::HWARO_E_CONFIG,
      message: "bad toml",
    )
    err.hint.should be_nil
    err.exit_code.should eq(3)
  end

  it "produces a stable JSON payload" do
    err = Hwaro::HwaroError.new(
      code: Hwaro::Errors::HWARO_E_NETWORK,
      message: "upload failed",
      hint: "check credentials",
    )
    payload = err.to_error_payload
    payload["status"].should eq("error")
    error = payload["error"]
    error["code"].should eq("HWARO_E_NETWORK")
    error["category"].should eq("network")
    error["message"].should eq("upload failed")
    error["hint"].should eq("check credentials")
  end
end
