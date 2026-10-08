require "../../spec_helper"

# ext/toml_float_fix.cr — floats are the correctly rounded double of the literal.
describe "TOML floats (ext/toml_float_fix)" do
  it "parses literals with 20+ digits" do
    TOML.parse("pi = 3.14159265358979323846264338327950288")["pi"].as_f.should eq(3.14159265358979323846264338327950288)
    TOML.parse("x = 0.000000000000000000001")["x"].as_f.should eq(1e-21)
    TOML.parse("x = 12345678901234567890.5")["x"].as_f.should eq(12345678901234567890.5)
    TOML.parse("x = 1.0000000000000000000000000001")["x"].as_f.should eq(1.0)
  end

  it "rounds exponent floats exactly once" do
    {"1.1e2" => 110.0, "1.1e-2" => 0.011, "6.022e23" => 6.022e23,
     "2.632e-28" => 2.632e-28, "3.40712710044172e+12" => 3.40712710044172e+12,
     "1.7976931348623157e308" => Float64::MAX, "-183.06195214323486" => -183.06195214323486,
     "5e-3" => 0.005, "1E3" => 1000.0}.each do |lit, want|
      TOML.parse("x = #{lit}")["x"].as_f.should eq(want)
    end
  end

  it "keeps underscores, signs and the existing validation" do
    TOML.parse("x = 1_000.000_1")["x"].as_f.should eq(1000.0001)
    TOML.parse("x = +1.5")["x"].as_f.should eq(1.5)
    TOML.parse("x = -0.5e1")["x"].as_f.should eq(-5.0)
    expect_raises(TOML::ParseException) { TOML.parse("x = 1.") }
    expect_raises(TOML::ParseException) { TOML.parse("x = 1.5e") }
    expect_raises(TOML::ParseException) { TOML.parse("x = 1__0.5") }
  end

  it "treats underflow as zero and overflow as an error" do
    TOML.parse("x = 1e-400")["x"].as_f.should eq(0.0)
    expect_raises(TOML::ParseException) { TOML.parse("x = 1e400") }
  end

  it "reports an integer that does not fit in 64 bits as a TOML error" do
    TOML.parse("x = 9223372036854775807")["x"].as_i64.should eq(Int64::MAX)
    TOML.parse("x = -9223372036854775808")["x"].as_i64.should eq(Int64::MIN)
    expect_raises(TOML::ParseException) { TOML.parse("x = 9223372036854775808") }
    expect_raises(TOML::ParseException) { TOML.parse("x = 99999999999999999999") }
  end
end
