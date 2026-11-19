require "../../spec_helper"

# Counts constructions, so an exception that is raised and swallowed inside
# the lexer is visible to the examples below.
class TOML::ParseException
  class_property hwaro_spec_constructed = 0

  def initialize(message, @line_number, @column_number)
    previous_def(message, @line_number, @column_number)
    @@hwaro_spec_constructed += 1
  end
end

# ext/toml_key_lex_perf.cr — bare words lex without a raised-and-rescued exception.
describe "TOML bare word lexing (ext/toml_key_lex_perf)" do
  it "raises no exception for keys and bare values after the first `=`" do
    before = TOML::ParseException.hwaro_spec_constructed
    t = TOML.parse(%(title = "Post"\ndate = "2024-01-01"\ndraft = false\ntoc = true\nweight = 3\ntags = ["a", "b"]\n[extra]\nfeatured = true\nx = { y = false }\n))
    TOML::ParseException.hwaro_spec_constructed.should eq(before)
    t["draft"].as_bool.should be_false
    t["toc"].as_bool.should be_true
    t["weight"].as_i.should eq(3)
    t["extra"]["featured"].as_bool.should be_true
    t["extra"]["x"]["y"].as_bool.should be_false
  end

  it "still reads inf and nan as floats in value position, and as keys in key position" do
    t = TOML.parse(%(a = 1\nb = inf\nc = nan\nd = [inf, nan]\ninf = 2\nnan = 3\n))
    t["b"].as_f.should eq(Float64::INFINITY)
    t["c"].as_f.nan?.should be_true
    t["d"].as_a[0].as_f.should eq(Float64::INFINITY)
    t["d"].as_a[1].as_f.nan?.should be_true
    t["inf"].as_i.should eq(2)
    t["nan"].as_i.should eq(3)
  end

  it "still rejects an unknown bare word as a value" do
    expect_raises(TOML::ParseException) { TOML.parse("a = 1\nb = infinity\n") }
    expect_raises(TOML::ParseException) { TOML.parse("a = 1\nb = maybe\n") }
  end
end
