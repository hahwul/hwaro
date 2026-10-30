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

    it "prints a float's shortest form in plain notation" do
      # Float#to_s writes these as "1.0e-7" / "2.0e-6"; the ".0" is not a digit.
      {1e-7 => "0.0000001", 2e-6 => "0.000002", 1234.0 => "1,234", 1.5e-7 => "0.00000015"}.each do |value, expected|
        render_crinja("{{ x | num_format }}", {"x" => Crinja::Value.new(value)}).should eq(expected)
      end
    end

    it "rounds half away from zero, without a negative zero" do
      render_crinja("{{ 1.005 | num_format(decimals=2) }}").should eq("1.01")
      render_crinja("{{ 2.5 | num_format(decimals=0) }}").should eq("3")
      render_crinja("{{ -2.5 | num_format(decimals=0) }}").should eq("-3")
      render_crinja("{{ 9999.996 | num_format(decimals=2) }}").should eq("10,000.00")
      render_crinja("{{ 999.999 | num_format(decimals=2) }}|{{ 0.995 | num_format(decimals=2) }}").should eq("1,000.00|1.00")
      # The float's shortest digits are rounded, not its binary value.
      render_crinja("{{ 2.675 | num_format(decimals=2) }}|{{ 0.125 | num_format(decimals=2) }}").should eq("2.68|0.13")
      render_crinja("{{ 1234.5678 | num_format(decimals=1) }}|{{ 0.5 | num_format(decimals=0) }}").should eq("1,234.6|1")
      render_crinja(%({{ "-0.004" | num_format(decimals=2) }}|{{ "-0" | num_format }})).should eq("0.00|0")
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
      render_crinja(%({{ "99999999999999999999.995" | num_format(decimals=2) }})).should eq("100,000,000,000,000,000,000.00")
      render_crinja(%({{ "007" | num_format }}|{{ "+1234.50" | num_format }}|{{ "0.000" | num_format }})).should eq("7|1,234.50|0.000")
      render_crinja("{{ x | num_format }}", {"x" => Crinja::Value.new(Int64::MIN)}).should eq("-9,223,372,036,854,775,808")
      render_crinja("{{ x | num_format }}", {"x" => Crinja::Value.new(0.1 + 0.2)}).should eq("0.30000000000000004")
      render_crinja("{{ x | num_format }}", {"x" => Crinja::Value.new(-1.5e20)}).should eq("-150,000,000,000,000,000,000")
    end

    it "returns anything that is not a number unchanged" do
      render_crinja(%({{ "abc" | num_format }})).should eq("abc")
      render_crinja(%({{ "1e3" | num_format }})).should eq("1e3")
      # Non-ASCII digits (`\d` matches them under UCP) are text, not numbers.
      render_crinja(%({{ "١٢٣٤" | num_format }}|{{ "１２３４" | num_format }})).should eq("١٢٣٤|１２３４")
      render_crinja(%(<{{ nope | num_format }}>)).should eq("<>")
      render_crinja(%({{ true | num_format }})).should eq("true")
      vars = {"x" => Crinja::Value.new(Float64::NAN), "y" => Crinja::Value.new(Float64::INFINITY)}
      render_crinja(%({{ x | num_format }}|{{ y | num_format }}), vars).should eq("NaN|Infinity")
    end

    it "clamps decimals= into 0..20" do
      render_crinja("{{ 1.5 | num_format(decimals=-3) }}").should eq("2")
      render_crinja("{{ 1 | num_format(decimals=99) }}").should eq("1." + "0" * 20)
    end

    it "accepts an integral decimals= string or float and ignores any other value" do
      render_crinja(%({{ 1.5 | num_format(decimals="2") }}|{{ 1.5 | num_format(decimals=2.0) }})).should eq("1.50|1.50")
      render_crinja(%({{ 1.25 | num_format(decimals="x") }}|{{ 1.25 | num_format(decimals=1.5) }}|{{ 1.25 | num_format(decimals=true) }}))
        .should eq("1.25|1.25|1.25")
    end
  end
end
