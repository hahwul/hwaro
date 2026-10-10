require "../../spec_helper"
require "../../../src/ext/crinja_striptags_fix"

private def render_striptags(source : String, vars = {} of String => Crinja::Value) : String
  Crinja.new.from_string(source).render(vars)
end

describe "Crinja `striptags` filter" do
  it "renders an empty or undefined input as empty instead of raising" do
    render_striptags(%([{{ "" | striptags }}][{{ missing | striptags }}])).should eq("[][]")
  end

  it "still strips tags and collapses whitespace" do
    render_striptags(%({{ "<p>a  <b>b</b>\n c</p>" | striptags }})).should eq("a b c")
  end
end
