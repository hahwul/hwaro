require "../../spec_helper"

private def render_escape(source : String) : String
  Crinja.new.from_string(source).render
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja string literal escapes" do
  it "decodes Python escapes" do
    render_escape(%q({{ 'a\tb' }})).should eq("a\tb")
    render_escape(%q({{ 'é\U0001F600\x41\101' }})).should eq("é😀AA")
    render_escape(%q({{ 'it\'s' ~ "q\"q" ~ 'a\\b' ~ 'a\nb' }})).should eq("it'sq\"qa\\ba\nb")
  end

  it "keeps the backslash of an unknown escape" do
    render_escape(%q({{ '\.png$' }}|{{ 'x\d+y' }})).should eq("\\.png$|x\\d+y")
  end

  it "treats backslash-newline as a line continuation" do
    render_escape("{{ 'a\\\nb' }}").should eq("ab")
  end

  it "keeps a malformed hex escape literally" do
    render_escape(%q({{ 'a\u00' }})).should eq("a\\u00")
  end
end
