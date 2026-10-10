require "../../spec_helper"

private def render_logic(source : String, vars = {} of String => Crinja::Value) : String
  Crinja.new.from_string(source).render(vars)
end

# Expected strings are Jinja2 3.1's output for the same source (Crinja
# prints booleans in lowercase).
describe "Crinja `and` / `or`" do
  it "returns the deciding operand" do
    render_logic("{{ 'a' or 'b' }}|{{ '' or 'b' }}|{{ 'a' and 'b' }}|{{ '' and 'b' }}").should eq("a|b|b|")
  end

  it "supports the fallback idiom with undefined values" do
    render_logic("{{ missing or 'fb' }}").should eq("fb")
    render_logic("{% set x = missing or 'fb' %}{{ x }}").should eq("fb")
    render_logic("{{ desc or 'site' }}", {"desc" => Crinja::Value.new("page")}).should eq("page")
  end

  it "keeps the operand's type" do
    render_logic("{{ (none or 0) is number }}").should eq("true")
    render_logic("{{ (0 or 2) + 1 }}").should eq("3")
  end

  it "leaves truthiness in conditions unchanged" do
    render_logic("{% if 0 or '' %}T{% else %}F{% endif %}{% if 'a' and 1 %}T{% endif %}").should eq("FT")
    render_logic("{% if missing is defined and missing.x %}T{% else %}F{% endif %}").should eq("F")
  end
end
