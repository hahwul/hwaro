require "../../spec_helper"

# ext/toml_syntax_fix.cr — valid TOML 1.0 the vendored lexer/parser rejected.
describe "TOML 1.0 syntax (ext/toml_syntax_fix)" do
  describe "\\u / \\U escapes" do
    it "reads exactly four hex digits for \\u" do
      # The char after the escape is a hex digit: upstream swallowed it.
      TOML.parse(%(a = "\\u00e9ab y"))["a"].as_s.should eq("éab y")
      TOML.parse(%(a = "\\u00e9abcd"))["a"].as_s.should eq("éabcd")
      TOML.parse(%(a = "\\u0001b"))["a"].as_s.should eq("\u0001b")
      TOML.parse(%(a = "\\u00e9"))["a"].as_s.should eq("é")
    end

    it "reads exactly eight hex digits for \\U" do
      TOML.parse(%(a = "\\U0001F600 hi"))["a"].as_s.should eq("😀 hi")
      TOML.parse(%(a = "\\U0001F600a"))["a"].as_s.should eq("😀a")
    end

    it "works in multi-line basic strings" do
      TOML.parse(%(a = """x\\u00e9a\\U0001F600"""))["a"].as_s.should eq("xéa😀")
    end

    it "rejects invalid scalars with a ParseException" do
      expect_raises(TOML::ParseException) { TOML.parse(%(a = "\\ud800")) }
      expect_raises(TOML::ParseException) { TOML.parse(%(a = "\\U00110000")) }
      expect_raises(TOML::ParseException) { TOML.parse(%(a = "\\u12")) }
      expect_raises(TOML::ParseException) { TOML.parse(%(a = "\\U0001F6")) }
    end
  end

  describe "empty inline table" do
    it "parses {}" do
      TOML.parse("a = {}")["a"].as_h.should be_empty
      TOML.parse("a = { b = {}, c = 1 }")["a"].as_h["b"].as_h.should be_empty
      TOML.parse("a = [{}, {x = 1}]")["a"].as_a.size.should eq(2)
      TOML.parse("a = {}\nb = 2")["b"].as_i.should eq(2)
    end

    it "still parses populated inline tables" do
      TOML.parse("a = { x = 1, y = 2 }")["a"].as_h["y"].as_i.should eq(2)
    end
  end

  describe "prefixed integers" do
    it "parses 0x / 0o / 0b" do
      TOML.parse("a = 0xDEADBEEF")["a"].as_i64.should eq(0xDEADBEEF)
      TOML.parse("a = 0xdead_beef")["a"].as_i64.should eq(0xDEADBEEF)
      TOML.parse("a = 0o755")["a"].as_i.should eq(0o755)
      TOML.parse("a = 0b1101")["a"].as_i.should eq(13)
      TOML.parse("a = [0x1, 0o7, 0b1]")["a"].as_a.map(&.as_i).should eq([1, 7, 1])
    end

    it "rejects malformed prefixed integers" do
      expect_raises(TOML::ParseException) { TOML.parse("a = 0x") }
      expect_raises(TOML::ParseException) { TOML.parse("a = 0o8") }
      expect_raises(TOML::ParseException) { TOML.parse("a = 0b12") }
      expect_raises(TOML::ParseException) { TOML.parse("a = 0xFFFFFFFFFFFFFFFFFF") }
    end

    it "leaves decimals, floats, dates and zero alone" do
      TOML.parse("a = 0")["a"].as_i.should eq(0)
      TOML.parse("a = 10")["a"].as_i.should eq(10)
      TOML.parse("a = -5")["a"].as_i.should eq(-5)
      TOML.parse("a = 0.5")["a"].as_f.should eq(0.5)
      TOML.parse("a = 1_000")["a"].as_i.should eq(1000)
      TOML.parse("a = 2024-03-05")["a"].raw.as(Time).year.should eq(2024)
      expect_raises(TOML::ParseException) { TOML.parse("a = 012") }
    end
  end
end
