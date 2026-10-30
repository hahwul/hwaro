require "../../../../spec_helper"
require "../../../../../src/content/processors/template"

describe Hwaro::Content::Processors::Filters::MathFilters do
  describe "num_format" do
    it "groups integer digits in threes" do
      render_crinja("{{ 1234567 | num_format }}").should eq("1,234,567")
      render_crinja("{{ 123 | num_format }}").should eq("123")
      render_crinja("{{ 0 | num_format }}").should eq("0")
      render_crinja("{{ -1234567 | num_format }}").should eq("-1,234,567")
      render_crinja("{{ 1000 | num_format }}").should eq("1,000")
    end

    it "keeps a float's own decimals unless decimals= is given" do
      render_crinja("{{ 1234.5 | num_format }}").should eq("1,234.5")
      render_crinja("{{ 1234.5 | num_format(decimals=2) }}").should eq("1,234.50")
      render_crinja("{{ 1234567 | num_format(decimals=2) }}").should eq("1,234,567.00")
      render_crinja("{{ 0.00000015 | num_format }}").should eq("0.00000015")
      render_crinja("{{ x | num_format }}", {"x" => Crinja::Value.new(1e20)}).should eq("100,000,000,000,000,000,000")
    end

    it "rounds half away from zero, without a negative zero" do
      render_crinja("{{ 1.005 | num_format(decimals=2) }}").should eq("1.01")
      render_crinja("{{ 2.5 | num_format(decimals=0) }}").should eq("3")
      render_crinja("{{ -2.5 | num_format(decimals=0) }}").should eq("-3")
      render_crinja("{{ 9999.996 | num_format(decimals=2) }}").should eq("10,000.00")
      render_crinja("{{ -0.001 | num_format(decimals=2) }}").should eq("0.00")
    end

    it "takes custom separator and decimal point" do
      render_crinja(%({{ 1234567.5 | num_format(separator=".", decimal_point=",") }})).should eq("1.234.567,5")
      render_crinja(%({{ 1234567 | num_format(separator=" ") }})).should eq("1 234 567")
      render_crinja(%({{ 1234567 | num_format(separator="") }})).should eq("1234567")
    end

    it "formats numeric strings exactly, beyond Int64" do
      render_crinja(%({{ " 1234567.25 " | num_format }})).should eq("1,234,567.25")
      render_crinja(%({{ "-98765432109876543210" | num_format }})).should eq("-98,765,432,109,876,543,210")
    end

    it "returns anything that is not a number unchanged" do
      render_crinja(%({{ "abc" | num_format }})).should eq("abc")
      render_crinja(%({{ "1e3" | num_format }})).should eq("1e3")
      render_crinja(%(<{{ nope | num_format }}>)).should eq("<>")
      render_crinja(%({{ true | num_format }})).should eq("true")
      vars = {"x" => Crinja::Value.new(Float64::NAN), "y" => Crinja::Value.new(Float64::INFINITY)}
      render_crinja(%({{ x | num_format }}|{{ y | num_format }}), vars).should eq("NaN|Infinity")
    end

    it "clamps decimals= into 0..20" do
      render_crinja("{{ 1.5 | num_format(decimals=-3) }}").should eq("2")
      render_crinja("{{ 1 | num_format(decimals=99) }}").should eq("1." + "0" * 20)
    end
  end
end
