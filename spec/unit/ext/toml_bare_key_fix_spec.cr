require "../../spec_helper"

# ext/toml_bare_key_fix.cr — TOML bare keys are A-Za-z0-9_-, whatever they look like.
describe "TOML bare keys (ext/toml_bare_key_fix)" do
  it "reads number-, sign- and constant-looking bare keys as keys" do
    t = TOML.parse(%(2024 = "a"\n1password = true\n-dash = 1\n1e3 = 2\n007 = 3\ninf = 4\nnan = 5\n0x1 = 6\n1_0 = 7\n2024-01-01 = 8\n))
    t["2024"].as_s.should eq("a")
    t["1password"].as_bool.should be_true
    {"-dash" => 1, "1e3" => 2, "007" => 3, "inf" => 4, "nan" => 5, "0x1" => 6, "1_0" => 7, "2024-01-01" => 8}.each do |k, v|
      t[k].as_i.should eq(v)
    end
  end

  it "applies in table headers, dotted keys and inline tables" do
    t = TOML.parse(%([2024]\nq = 1\n[[1]]\n-x = 2\n[a.1e3.b]\nc = 1\n[d]\n1.2 = 3\ne = { 1a = 1, inf = 2, -z = 3 }\n))
    t["2024"]["q"].as_i.should eq(1)
    t["1"].as_a[0]["-x"].as_i.should eq(2)
    t["a"]["1e3"]["b"]["c"].as_i.should eq(1)
    t["d"]["1"]["2"].as_i.should eq(3)
    t["d"]["e"]["1a"].as_i.should eq(1)
    t["d"]["e"]["inf"].as_i.should eq(2)
    t["d"]["e"]["-z"].as_i.should eq(3)
  end

  it "leaves values lexing alone, including numbers on array continuation lines" do
    t = TOML.parse(%(a = [\n  1,\n  -2,\n  3.5,\n]\nb = -inf\nc = nan\nd = 1979-05-27\ne = [[1, 2], [3]]\nf = [ { 1 = 2 }, { 3 = 4 } ]\n))
    t["a"].as_a.map(&.raw).should eq([1_i64, -2_i64, 3.5])
    t["b"].as_f.should eq(-Float64::INFINITY)
    t["c"].as_f.nan?.should be_true
    t["d"].raw.should be_a(Time)
    t["e"].as_a.size.should eq(2)
    t["f"].as_a[1]["3"].as_i.should eq(4)
  end
end
