require "../../spec_helper"
require "../../../src/hwaro"

# Regression coverage for the crash-hardening pass: inputs that used to abort a
# command with an UNCLASSIFIED exception (a bare stdlib ArgumentError /
# OverflowError surfacing as `Error: <stdlib message>` — no code, no file, no
# hint) now produce a classified error or a defined fallback.

# `File.tempfile`'s block form closes the file but does NOT delete it, and the
# deep-dotted-key examples below write multi-megabyte configs — so clean up
# explicitly rather than leaving a pile of them in the system temp dir.
# As written in a config file: a well-formed TOML escape that decodes to a NUL.
TOML_NUL = "x\\u0000z"
# The decoded string a Crystal caller would hold.
RAW_NUL = "x#{Char::ZERO}z"

describe "crash hardening" do
  # ---------------------------------------------------------------------------
  # NUL bytes in config strings.
  #
  # The escape survives TOML parsing, so the NUL reached every consumer of the
  # value. Anything that then built a Path from it raised
  # `ArgumentError: String contains null byte` out of stdlib's
  # check_no_null_byte — reported as the unclassified
  # `Error: String contains null byte`, naming neither the key nor the file.
  # `validate_output_filename!` could not catch it either: its own
  # `File.basename(value)` operand raised before the NUL test it guarded ran.
  # ---------------------------------------------------------------------------
  describe "Config.load with a NUL byte in a string value" do
    {
      "build.output_dir"         => %([build]\noutput_dir = "#{TOML_NUL}"\n),
      "sitemap.filename"         => %([sitemap]\nenabled = true\nfilename = "#{TOML_NUL}"\n),
      "robots.filename"          => %([robots]\nfilename = "#{TOML_NUL}"\n),
      "llms.filename"            => %([llms]\nfilename = "#{TOML_NUL}"\n),
      "llms.full_filename"       => %([llms]\nfull_filename = "#{TOML_NUL}"\n),
      "feeds.filename"           => %([feeds]\nfilename = "#{TOML_NUL}"\n),
      "search.filename"          => %([search]\nfilename = "#{TOML_NUL}"\n),
      "og.auto_image.output_dir" => %([og.auto_image]\noutput_dir = "#{TOML_NUL}"\n),
    }.each do |key, toml|
      it "raises a classified config error naming #{key}" do
        err = expect_raises(Hwaro::HwaroError) { load_config(toml) }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain(key)
        (err.message || "").should contain("NUL")
      end
    end

    it "reports a NUL inside an array element with its index" do
      err = expect_raises(Hwaro::HwaroError) do
        load_config(%([sitemap]\nenabled = true\nexclude = ["ok", "#{TOML_NUL}"]\n))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("sitemap.exclude[1]")
    end

    it "reports a NUL in a plain (non-path) string too" do
      err = expect_raises(Hwaro::HwaroError) { load_config(%(title = "#{TOML_NUL}"\n)) }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("title")
    end

    # `[a.b.c…]` builds one nested table per dotted segment and never enters
    # `parse_value`, so ext/toml_nesting_limit_fix.cr's cap does not apply: the
    # parser accepts a 50k-segment header. A RECURSIVE scan of the result
    # overflowed the stack — unrescuable, and on a config the section loaders
    # never descend into. The scan is iterative for exactly this reason.
    it "scans a pathologically deep dotted-key table without overflowing" do
      deep = Array.new(20_000) { |i| "k#{i}" }.join('.')
      config = load_config("[#{deep}]\nx = 1\n")
      config.title.should_not be_nil
    end

    it "still finds a NUL buried in a pathologically deep table" do
      deep = Array.new(20_000) { |i| "k#{i}" }.join('.')
      err = expect_raises(Hwaro::HwaroError) { load_config(%([#{deep}]\nx = "#{TOML_NUL}"\n)) }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("NUL")
    end

    # A quoted TOML key carries the escape exactly as a value does, and both
    # `[languages.<code>]` and `[menus.<name>]` keys are joined into output
    # paths downstream.
    it "rejects a NUL in a quoted table key" do
      err = expect_raises(Hwaro::HwaroError) do
        load_config(%([languages."e#{TOML_NUL}n"]\nlanguage_name = "En"\n))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("NUL")
    end

    it "rejects a NUL in a top-level key" do
      err = expect_raises(Hwaro::HwaroError) { load_config(%("a#{TOML_NUL}b" = 1\n)) }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end

    it "rejects a NUL in an inline-table key" do
      err = expect_raises(Hwaro::HwaroError) do
        load_config(%([markdown]\nx = { "k#{TOML_NUL}y" = 1 }\n))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end

    it "leaves NUL-free configs untouched" do
      config = load_config(%(title = "ok"\n[sitemap]\nenabled = true\nfilename = "sitemap.xml"\n))
      config.title.should eq("ok")
      config.sitemap.filename.should eq("sitemap.xml")
    end
  end

  # ---------------------------------------------------------------------------
  # OutputGuard: a SAFETY predicate must answer, never raise. File.expand_path
  # builds a Path, so a NUL made both entry points abort the build instead of
  # reporting "not inside the output directory".
  # ---------------------------------------------------------------------------
  describe Hwaro::Utils::OutputGuard do
    it "returns nil for an output path containing a NUL byte" do
      Hwaro::Utils::OutputGuard.safe_output_path("public/#{RAW_NUL}.html", "public").should be_nil
    end

    it "returns nil when the output DIRECTORY contains a NUL byte" do
      Hwaro::Utils::OutputGuard.safe_output_path("public/a.html", RAW_NUL).should be_nil
    end

    it "answers false instead of raising for a NUL path" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/#{RAW_NUL}.html", "public").should be_false
      Hwaro::Utils::OutputGuard.within_output_dir?("public/a.html", RAW_NUL).should be_false
    end
  end

  # ---------------------------------------------------------------------------
  # TextUtils formatting helpers: both raised on out-of-range integer inputs.
  # truncate_error runs while REPORTING another failure, so a raise there
  # replaces a real diagnostic with a stdlib message.
  # ---------------------------------------------------------------------------
  describe Hwaro::Utils::TextUtils do
    it "clamps a negative truncate_error budget instead of raising" do
      result = Hwaro::Utils::TextUtils.truncate_error("template failed", -1)
      result.should contain("truncated")
      result.should contain("15 characters")
    end

    it "keeps a zero budget usable" do
      Hwaro::Utils::TextUtils.truncate_error("abc", 0).should start_with("…")
    end

    it "does not overflow pad_display at the Int32 extremes" do
      Hwaro::Utils::TextUtils.pad_display("ab", Int32::MIN).should eq("ab")
      Hwaro::Utils::TextUtils.pad_display("ab", Int32::MAX).size.should be <= 10_002 # 2 + MAX_PAD_COLUMNS
    end

    it "still pads normally" do
      Hwaro::Utils::TextUtils.pad_display("ab", 5).should eq("ab   ")
      Hwaro::Utils::TextUtils.pad_display("abcdef", 3).should eq("abcdef")
    end
  end
end
