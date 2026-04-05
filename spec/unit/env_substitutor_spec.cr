require "../spec_helper"

describe Hwaro::Utils::EnvSubstitutor do
  describe ".substitute" do
    it "substitutes ${VAR} with environment variable value" do
      ENV["HWARO_TEST_URL"] = "https://example.com"
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("base_url = \"${HWARO_TEST_URL}\"")
      result.should eq("base_url = \"https://example.com\"")
      missing.should be_empty
    ensure
      ENV.delete("HWARO_TEST_URL")
    end

    it "substitutes bare $VAR with environment variable value" do
      ENV["HWARO_TEST_TITLE"] = "My Site"
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("title = \"$HWARO_TEST_TITLE\"")
      result.should eq("title = \"My Site\"")
      missing.should be_empty
    ensure
      ENV.delete("HWARO_TEST_TITLE")
    end

    it "uses default value when env var is not set" do
      ENV.delete("HWARO_UNSET_VAR")
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("url = \"${HWARO_UNSET_VAR:-https://default.com}\"")
      result.should eq("url = \"https://default.com\"")
      missing.should be_empty
    end

    it "uses default value when env var is empty" do
      ENV["HWARO_EMPTY_VAR"] = ""
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("url = \"${HWARO_EMPTY_VAR:-fallback}\"")
      result.should eq("url = \"fallback\"")
      missing.should be_empty
    ensure
      ENV.delete("HWARO_EMPTY_VAR")
    end

    it "supports empty default value" do
      ENV.delete("HWARO_UNSET_VAR2")
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("key = \"${HWARO_UNSET_VAR2:-}\"")
      result.should eq("key = \"\"")
      missing.should be_empty
    end

    it "reports missing variables without defaults" do
      ENV.delete("HWARO_MISSING_VAR")
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("key = \"${HWARO_MISSING_VAR}\"")
      result.should eq("key = \"${HWARO_MISSING_VAR}\"")
      missing.should eq(["HWARO_MISSING_VAR"])
    end

    it "reports missing bare $VAR" do
      ENV.delete("HWARO_MISSING_BARE")
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("key = \"$HWARO_MISSING_BARE\"")
      result.should eq("key = \"$HWARO_MISSING_BARE\"")
      missing.should eq(["HWARO_MISSING_BARE"])
    end

    it "handles multiple substitutions in one string" do
      ENV["HWARO_A"] = "hello"
      ENV["HWARO_B"] = "world"
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("${HWARO_A} ${HWARO_B}")
      result.should eq("hello world")
      missing.should be_empty
    ensure
      ENV.delete("HWARO_A")
      ENV.delete("HWARO_B")
    end

    it "does not substitute when no env var patterns present" do
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("plain text without vars")
      result.should eq("plain text without vars")
      missing.should be_empty
    end

    it "prefers env var value over default when var is set" do
      ENV["HWARO_WITH_DEFAULT"] = "actual"
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("${HWARO_WITH_DEFAULT:-fallback}")
      result.should eq("actual")
      missing.should be_empty
    ensure
      ENV.delete("HWARO_WITH_DEFAULT")
    end

    it "deduplicates missing variable names" do
      ENV.delete("HWARO_DUP")
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("${HWARO_DUP} and ${HWARO_DUP}")
      missing.size.should eq(1)
      missing.should eq(["HWARO_DUP"])
    end

    it "does not double-substitute values containing dollar signs" do
      ENV["HWARO_PRICE"] = "costs $USD100"
      ENV.delete("USD100")
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("item ${HWARO_PRICE}")
      result.should eq("item costs $USD100")
      missing.should be_empty
    ensure
      ENV.delete("HWARO_PRICE")
    end

    it "substitutes ${VAR} with empty string when var is set to empty" do
      ENV["HWARO_EMPTY_SET"] = ""
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("val = \"${HWARO_EMPTY_SET}\"")
      result.should eq("val = \"\"")
      missing.should be_empty
    ensure
      ENV.delete("HWARO_EMPTY_SET")
    end

    it "substitutes bare $VAR with empty string when var is set to empty" do
      ENV["HWARO_EMPTY_BARE"] = ""
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("val = \"$HWARO_EMPTY_BARE\"")
      result.should eq("val = \"\"")
      missing.should be_empty
    ensure
      ENV.delete("HWARO_EMPTY_BARE")
    end

    it "allows balanced braces in default value" do
      result, missing = Hwaro::Utils::EnvSubstitutor.substitute("${HWARO_UNSET_JSON:-{\"key\": 1}}")
      result.should eq("{\"key\": 1}")
      missing.should be_empty
    end
  end
end
