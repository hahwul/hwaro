require "../../spec_helper"

private def render_paren(source : String) : String
  Crinja.new.from_string(source).render({
    "pages" => Crinja.value([{"title" => "A", "tags" => ["x", "y"]}, {"title" => "B", "tags" => [] of String}]),
  })
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja access after a parenthesized expression" do
  it "reads an attribute, subscript or call after the closing parenthesis" do
    render_paren("{{ (pages | first).title }}|{{ (pages | last)['title'] }}|{{ (pages | first).tags[1] }}").should eq("A|B|y")
    render_paren("{{ ([1, 2, 3] | reverse | list)[0] }}|{{ ({'a': {'b': 3}}).a.b }}").should eq("3|3")
    render_paren("{{ ((pages | first).tags | first) }}|{{ (pages | first).title | lower }}").should eq("x|a")
  end

  it "keeps plain grouping and tuples" do
    render_paren("{{ (1 + 2) * 3 }}|{{ (1, 2)[1] }}|{{ ((2)) }}|{{ -(1 + 2) }}").should eq("9|2|2|-3")
  end
end
