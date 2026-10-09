require "../../spec_helper"

# ext/toml_parser_fix.cr — table headers, arrays and inline tables.
describe "TOML parser (ext/toml_parser_fix)" do
  # Regression: a header's last segment was looked up in the ROOT table, so a
  # root-level array whose key matched it ("tags") rejected `[extra.tags]`.
  describe "table header next to a same-named root array" do
    it "accepts [b.a] after a = [1]" do
      doc = TOML.parse("a = [1]\n[b.a]\nx = 1\n")
      doc["a"].as_a.map(&.as_i).should eq([1])
      doc["b"].as_h["a"].as_h["x"].as_i.should eq(1)
    end

    it "accepts front matter shaped like tags + [extra.tags]" do
      doc = TOML.parse("title = \"T\"\ntags = [\"a\"]\n\n[extra]\nfoo = 1\n\n[extra.tags]\ncolor = \"red\"\n")
      doc["extra"].as_h["tags"].as_h["color"].as_s.should eq("red")
    end

    it "still rejects re-opening a static array as a table" do
      expect_raises(TOML::ParseException) { TOML.parse("a = [1]\n[a]\n") }
      expect_raises(TOML::ParseException) { TOML.parse("[b]\na = [1]\n[b.a]\n") }
    end
  end

  describe "empty inline table" do
    it "parses {}" do
      TOML.parse("x = {}")["x"].as_h.should be_empty
      TOML.parse("[extra]\nlist = {}\nn = 1\n")["extra"].as_h["n"].as_i.should eq(1)
      TOML.parse("x = [{}, {a = 1}]")["x"].as_a.size.should eq(2)
    end

    it "still parses non-empty tables" do
      TOML.parse("x = {a = 1,}")["x"].as_h["a"].as_i.should eq(1)
      TOML.parse("x = { a = 1, b = 2 }")["x"].as_h.size.should eq(2)
    end

    it "still rejects a lone comma" do
      expect_raises(TOML::ParseException) { TOML.parse("x = {,}") }
    end
  end

  describe "arrays spanning lines" do
    it "allows a comment line before ]" do
      TOML.parse("tags = [\n  \"a\",\n  \"b\"\n  # \"c\"\n]")["tags"].as_a.map(&.as_s).should eq(["a", "b"])
      TOML.parse("n = [1, 2\n# c\n]")["n"].as_a.map(&.as_i).should eq([1, 2])
    end

    it "allows a leading comma on the next line" do
      TOML.parse("tags = [\n \"a\"\n , \"b\"\n]")["tags"].as_a.map(&.as_s).should eq(["a", "b"])
    end

    it "still rejects missing separators" do
      expect_raises(TOML::ParseException) { TOML.parse("x = [1 2]") }
      expect_raises(TOML::ParseException) { TOML.parse("x = [1\n2]") }
    end
  end
end
