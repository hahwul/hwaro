require "../../../spec_helper"

# =============================================================================
# BuildOptions#batch_size — `--memory-limit` validation
#
# A bad value used to raise a plain String exception, surfacing as a bare
# `Error: …` with exit 1 instead of the classified HWARO_E_USAGE / exit 2
# envelope every other flag error gets (compare `CLI.register_jobs`).
# =============================================================================

private def batch_size_for(limit : String)
  Hwaro::Config::Options::BuildOptions.new(memory_limit: limit).batch_size
end

describe Hwaro::Config::Options::BuildOptions do
  describe "#batch_size with an invalid --memory-limit" do
    it "raises a classified usage error for a malformed value" do
      err = expect_raises(Hwaro::HwaroError) { batch_size_for("bogus") }
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      (err.message || "").should contain("Invalid memory limit format")
    end

    it "raises a classified usage error for a zero size" do
      err = expect_raises(Hwaro::HwaroError) { batch_size_for("0") }
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      (err.message || "").should contain("Invalid memory limit")
    end

    it "raises a classified usage error for an overflowing size" do
      err = expect_raises(Hwaro::HwaroError) { batch_size_for("99999999999G") }
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
      (err.message || "").should contain("too large")
    end

    it "exits 2 like every other usage error" do
      err = expect_raises(Hwaro::HwaroError) { batch_size_for("bogus") }
      err.exit_code.should eq(2)
    end

    it "carries an actionable hint" do
      err = expect_raises(Hwaro::HwaroError) { batch_size_for("bogus") }
      (err.hint || "").should contain("--memory-limit")
    end
  end

  describe "#batch_size with a valid --memory-limit" do
    it "still parses suffixed sizes" do
      # ~50KB per page, so bytes // 51200.
      batch_size_for("2G").should eq((2_i64 * 1024 * 1024 * 1024 // (50 * 1024)).to_i32)
      batch_size_for("512M").should eq((512_i64 * 1024 * 1024 // (50 * 1024)).to_i32)
    end

    it "clamps a tiny limit to at least one page per batch" do
      batch_size_for("1K").should eq(1)
    end

    it "defaults to 500 without a limit" do
      Hwaro::Config::Options::BuildOptions.new.batch_size.should eq(500)
    end
  end
end
