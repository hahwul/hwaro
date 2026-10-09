require "../../spec_helper"

# ext/toml_parser_fix.cr — TOML 1.0 allows arrays of mixed types.
describe "TOML mixed-type arrays (ext/toml_parser_fix)" do
  it "parses a mixed scalar array" do
    TOML.parse("n = [1, 2.5]")["n"].as_a.map(&.raw).should eq([1_i64, 2.5])
    TOML.parse(%(m = ["a", 1, true]))["m"].as_a.map(&.raw).should eq(["a", 1_i64, true])
  end

  it "parses scalars mixed with tables and arrays" do
    TOML.parse(%(m = ["a", {k = 1}, [1, 2]]))["m"].as_a.size.should eq(3)
  end
end
